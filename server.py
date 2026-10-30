#!/usr/bin/env python3
"""Local classroom attendance server. Python standard library only."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hmac
import io
import json
import os
import secrets
import socket
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("ATTENDANCE_DB", ROOT / "data" / "attendance.sqlite3"))
ADMIN_PASSWORD = "hello"
MATCH_LIMIT = 0.90
QR_LIFETIME_MS = 1000
tokens: dict[str, tuple[str, str]] = {}
active_sessions: dict[str, dict] = {}
sheet_queue_lock = threading.Lock()
sheet_sync_pending: set[str] = set()
sheet_sync_running: set[str] = set()


def connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    return db


def initialize():
    with connect() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS roster (
          roll_no TEXT PRIMARY KEY, full_name TEXT NOT NULL,
          claimed INTEGER NOT NULL DEFAULT 0, course_code TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS app_settings (
          setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS course_sheets (
          course_name TEXT PRIMARY KEY COLLATE NOCASE,
          web_app_url TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS course_roster (
          course_name TEXT NOT NULL COLLATE NOCASE,
          roll_no TEXT NOT NULL,
          PRIMARY KEY(course_name, roll_no),
          FOREIGN KEY(roll_no) REFERENCES roster(roll_no) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS students (
          roll_no TEXT PRIMARY KEY, full_name TEXT NOT NULL,
          embedding TEXT, enrolled_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS change_requests (
          id INTEGER PRIMARY KEY AUTOINCREMENT, roll_no TEXT NOT NULL,
          requested_roll_no TEXT, requested_name TEXT, embedding TEXT,
          reset_registration INTEGER NOT NULL DEFAULT 0,
          reason TEXT NOT NULL, created_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending'
        );
        CREATE TABLE IF NOT EXISTS audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT, roll_no TEXT NOT NULL,
          action TEXT NOT NULL, details TEXT NOT NULL, created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS class_sessions (
          id TEXT PRIMARY KEY, course_code TEXT NOT NULL, title TEXT NOT NULL,
          started_at INTEGER NOT NULL, ended_at INTEGER,
          session_type TEXT NOT NULL DEFAULT 'class',
          duration_hours REAL NOT NULL DEFAULT 1.5,
          sheet_synced INTEGER NOT NULL DEFAULT 0,
          sheet_error TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS attendance (
          id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
          roll_no TEXT NOT NULL, full_name TEXT NOT NULL, checked_in_at INTEGER NOT NULL,
          embedding_distance REAL NOT NULL,
          UNIQUE(session_id, roll_no),
          FOREIGN KEY(session_id) REFERENCES class_sessions(id)
        );
        """)
        # Upgrade databases created by earlier app versions in place.
        session_columns = {row[1] for row in db.execute("PRAGMA table_info(class_sessions)")}
        if "session_type" not in session_columns:
            db.execute("ALTER TABLE class_sessions ADD COLUMN session_type TEXT NOT NULL DEFAULT 'class'")
        if "duration_hours" not in session_columns:
            db.execute("ALTER TABLE class_sessions ADD COLUMN duration_hours REAL NOT NULL DEFAULT 1.5")
        if "sheet_synced" not in session_columns:
            db.execute("ALTER TABLE class_sessions ADD COLUMN sheet_synced INTEGER NOT NULL DEFAULT 0")
        if "sheet_error" not in session_columns:
            db.execute("ALTER TABLE class_sessions ADD COLUMN sheet_error TEXT NOT NULL DEFAULT ''")
        request_columns = {row[1] for row in db.execute("PRAGMA table_info(change_requests)")}
        if "reset_registration" not in request_columns:
            db.execute("ALTER TABLE change_requests ADD COLUMN reset_registration INTEGER NOT NULL DEFAULT 0")
        import_courses_file(db)
        db.execute("""INSERT OR IGNORE INTO course_roster(course_name,roll_no)
            SELECT course_code,roll_no FROM roster WHERE course_code<>'' AND course_code<>'STARTER'""")
        starter_roster = [
            ("25BCS099", "Neel Rathod", "STARTER"),
            ("25BCS001", "Sample Student 001", "STARTER"),
            ("25BCS002", "Sample Student 002", "STARTER"),
            ("25BCS003", "Sample Student 003", "STARTER"),
            ("25BCS004", "Sample Student 004", "STARTER"),
            ("25BCS005", "Sample Student 005", "STARTER"),
        ]
        seeded = db.execute("SELECT 1 FROM app_settings WHERE setting_key='starter_roster_seeded'").fetchone()
        if not seeded:
            db.executemany(
                "INSERT INTO roster(roll_no,full_name,course_code) VALUES(?,?,?) "
                "ON CONFLICT(roll_no) DO NOTHING",
                starter_roster,
            )
            db.execute("INSERT INTO app_settings(setting_key,setting_value) VALUES('starter_roster_seeded','1')")
        # A running QR nonce is held in memory. If the process restarted, close
        # stale sessions so the dashboard doesn't show a dead session as live.
        db.execute(
            "UPDATE class_sessions SET ended_at=? WHERE ended_at IS NULL",
            (int(time.time() * 1000),),
        )


def embedding_vector(value):
    if not isinstance(value, list) or len(value) != 192:
        raise ValueError("Face vector must contain exactly 192 numbers.")
    vector = [float(item) for item in value]
    if not all(map(lambda item: item == item and abs(item) < 1000, vector)):
        raise ValueError("Face vector contains invalid values.")
    return vector


def distance(left, right):
    return sum((a - b) ** 2 for a, b in zip(left, right)) ** 0.5


def import_courses_file(db):
    """Load course-to-Sheets mappings from courses.csv when it exists."""
    path = ROOT / "courses.csv"
    if not path.is_file():
        return
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as source:
            reader = csv.DictReader(source)
            columns = {field.strip().lower(): field for field in (reader.fieldnames or [])}
            if not {"course_name", "web_app_url"}.issubset(columns):
                print("[COURSES] courses.csv needs course_name,web_app_url columns.")
                return
            imported = 0
            for row in reader:
                name = str(row.get(columns["course_name"], "")).strip()
                url = str(row.get(columns["web_app_url"], "")).strip()
                parsed = urlparse(url)
                if (not name or parsed.scheme != "https" or parsed.netloc != "script.google.com"
                        or not parsed.path.startswith("/macros/s/") or not parsed.path.endswith("/exec")):
                    continue
                db.execute("""INSERT INTO course_sheets(course_name,web_app_url) VALUES(?,?)
                    ON CONFLICT(course_name) DO UPDATE SET web_app_url=excluded.web_app_url""", (name, url))
                imported += 1
            if imported:
                print(f"[COURSES] Loaded {imported} course link(s) from courses.csv.")
    except (OSError, csv.Error) as error:
        print(f"[COURSES] Could not read courses.csv: {error}")


def course_sheet_url(db, course_name):
    row = db.execute("SELECT web_app_url FROM course_sheets WHERE course_name=?", (course_name,)).fetchone()
    return row[0] if row else ""


def sync_session_to_google_sheet(session_id):
    """Send session metadata and checked-in roll numbers; SQLite remains authoritative."""
    with connect() as db:
        session = db.execute("SELECT * FROM class_sessions WHERE id=?", (session_id,)).fetchone()
        if not session:
            return False, "Class session not found."
        web_app_url = course_sheet_url(db, session["course_code"])
        attendance = db.execute("SELECT roll_no,full_name,checked_in_at FROM attendance WHERE session_id=?", (session_id,)).fetchall()
    if not web_app_url:
        message = "No Google Sheets web app is configured for this course; attendance remains saved locally."
        with connect() as db:
            db.execute("UPDATE class_sessions SET sheet_synced=0,sheet_error=? WHERE id=?", (message, session_id))
        return False, message
    payload = {
        "action": "syncSession",
        "session": {
            "date": dt.datetime.fromtimestamp(session["started_at"] / 1000).astimezone().date().isoformat(),
            "classType": session["session_type"],
            "durationHours": session["duration_hours"],
        },
        # Send only the session metadata and the roll numbers that checked in.
        # The Google Sheet already owns the roster; never append the local roster.
        "attendance": [{"rollNo": row["roll_no"]} for row in attendance],
    }
    try:
        request = urllib.request.Request(
            web_app_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.loads(response.read().decode("utf-8"))
        if not result.get("ok"):
            raise RuntimeError(result.get("error", "Google Sheets rejected the update."))
        message = "Google Sheet updated."
        with connect() as db:
            db.execute("UPDATE class_sessions SET sheet_synced=1,sheet_error='' WHERE id=?", (session_id,))
        return True, message
    except (OSError, urllib.error.URLError, ValueError, RuntimeError) as error:
        message = f"Google Sheets update failed: {error}"
        with connect() as db:
            db.execute("UPDATE class_sessions SET sheet_synced=0,sheet_error=? WHERE id=?", (message[:500], session_id))
        return False, message


def queue_google_sheet_sync(session_id):
    with sheet_queue_lock:
        sheet_sync_pending.add(session_id)
        if session_id in sheet_sync_running:
            return
        sheet_sync_running.add(session_id)

    def worker():
        while True:
            with sheet_queue_lock:
                if session_id not in sheet_sync_pending:
                    sheet_sync_running.discard(session_id)
                    return
                sheet_sync_pending.discard(session_id)
            sync_session_to_google_sheet(session_id)

    threading.Thread(target=worker, daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    server_version = "AttendanceLAN/1.0"

    def log_message(self, fmt, *args):
        print("[HTTP] " + fmt % args)

    def send_json(self, status, value):
        raw = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self):
        self.send_json(200, {"ok": True})

    def body(self):
        size = int(self.headers.get("Content-Length", "0"))
        if size > 2_000_000:
            raise ValueError("Request is too large.")
        return json.loads(self.rfile.read(size) or b"{}")

    def require_token(self, role=None):
        raw = self.headers.get("Authorization", "")
        token = raw.removeprefix("Bearer ")
        identity = tokens.get(token)
        if not identity or (role and identity[0] != role):
            raise PermissionError("Sign in again to continue.")
        return identity

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/api/admin/requests", "/api/admin/sessions", "/api/admin/courses", "/api/admin/attendance.csv", "/api/admin/sheets/status") or (
            path.startswith("/api/sessions/") and path.endswith("/attendance")
        ):
            try:
                self.require_token("admin")
            except PermissionError as error:
                return self.send_json(401, {"error": str(error)})
        if path == "/api/health":
            return self.send_json(200, {
                "ok": True,
                "serverTime": int(time.time() * 1000),
                "server": "AttendanceLAN/1.0",
            })
        if path == "/api/admin/requests":
            self.require_token("admin")
            with connect() as db:
                rows = db.execute("""SELECT r.*, s.full_name, s.embedding IS NOT NULL AS enrolled
                    FROM change_requests r JOIN students s USING(roll_no)
                    WHERE r.status='pending' ORDER BY r.created_at""").fetchall()
            return self.send_json(200, [dict(row) for row in rows])
        if path.startswith("/api/sessions/") and path.endswith("/token"):
            session_id = path.split("/")[3]
            current = active_sessions.get(session_id)
            if not current:
                return self.send_json(404, {"error": "Class session is not active."})
            now = int(time.time() * 1000)
            if now - current["ts"] >= 1000:
                current["nonce"] = secrets.randbelow(900_000) + 100_000
                current["ts"] = now
            return self.send_json(200, {"session": current["course"], "sessionId": session_id,
                                        "nonce": current["nonce"], "ts": current["ts"]})
        if path.startswith("/api/sessions/") and path.endswith("/attendance"):
            session_id = path.split("/")[3]
            with connect() as db:
                rows = db.execute("SELECT roll_no, full_name, checked_in_at FROM attendance WHERE session_id=? ORDER BY checked_in_at DESC", (session_id,)).fetchall()
            return self.send_json(200, [dict(row) for row in rows])
        if path == "/api/admin/sessions":
            self.require_token("admin")
            with connect() as db:
                rows = db.execute("""SELECT s.*, (SELECT COUNT(*) FROM attendance a WHERE a.session_id=s.id) AS count
                    FROM class_sessions s ORDER BY started_at DESC LIMIT 30""").fetchall()
            return self.send_json(200, [dict(row) for row in rows])
        if path == "/api/admin/courses":
            self.require_token("admin")
            with connect() as db:
                rows = db.execute("SELECT course_name,web_app_url FROM course_sheets ORDER BY course_name COLLATE NOCASE").fetchall()
            return self.send_json(200, [{"courseName": row[0], "webAppUrl": row[1]} for row in rows])
        if path == "/api/admin/sheets/status":
            self.require_token("admin")
            with connect() as db:
                pending = db.execute("SELECT COUNT(*) FROM class_sessions WHERE ended_at IS NOT NULL AND sheet_synced=0").fetchone()[0]
                error = db.execute("SELECT sheet_error FROM class_sessions WHERE ended_at IS NOT NULL AND sheet_synced=0 AND sheet_error<>'' ORDER BY started_at DESC LIMIT 1").fetchone()
                configured = db.execute("SELECT COUNT(*) FROM course_sheets").fetchone()[0]
            return self.send_json(200, {
                "configured": configured > 0,
                "pendingSessions": pending,
                "lastError": error[0] if error else "",
            })
        if path == "/api/admin/attendance.csv":
            self.require_token("admin")
            course_name = parse_qs(urlparse(self.path).query).get("courseName", [""])[0].strip()
            if not course_name:
                return self.send_json(400, {"error": "Select a course before exporting its attendance."})
            with connect() as db:
                students = db.execute("""SELECT r.roll_no,r.full_name FROM course_roster cr
                    JOIN roster r USING(roll_no) WHERE cr.course_name=? ORDER BY r.roll_no""", (course_name,)).fetchall()
                sessions = db.execute("""SELECT id,started_at,session_type,duration_hours FROM class_sessions
                    WHERE course_code=? ORDER BY started_at,id""", (course_name,)).fetchall()
                attendance = db.execute("""SELECT a.session_id,a.roll_no FROM attendance a
                    JOIN class_sessions s ON s.id=a.session_id WHERE s.course_code=?""", (course_name,)).fetchall()
            present = {(row["session_id"], row["roll_no"]) for row in attendance}
            output = io.StringIO(newline="")
            writer = csv.writer(output)
            event_headers = [
                f"{dt.datetime.fromtimestamp(row['started_at'] / 1000).astimezone().date().isoformat()} {row['session_type'].title()}"
                for row in sessions
            ]
            writer.writerow(["Name", "Roll No", *event_headers])
            for student in students:
                values = [
                    row["duration_hours"] if (row["id"], student["roll_no"]) in present else ""
                    for row in sessions
                ]
                writer.writerow([student["full_name"], student["roll_no"], *values])
            raw = output.getvalue().encode("utf-8-sig")
            self.send_response(200)
            self.send_header("Content-Type", "text/csv; charset=utf-8")
            self.send_header("Content-Disposition", f"attachment; filename=attendance_{dt.date.today().isoformat()}.csv")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)
            return
        if path == "/":
            raw = (ROOT / "index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)
            return
        if path == "/assets/qrcode.min.js":
            raw = (ROOT / "assets" / "qrcode.min.js").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(raw)
            return
        self.send_json(404, {"error": "Not found."})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = self.body()
            if path == "/api/admin/login":
                if not ADMIN_PASSWORD:
                    return self.send_json(503, {"error": "Set ATTENDANCE_ADMIN_PASSWORD before starting the server."})
                if not hmac.compare_digest(str(data.get("password", "")), ADMIN_PASSWORD):
                    return self.send_json(401, {"error": "Administrator password is incorrect."})
                token = secrets.token_urlsafe(32)
                tokens[token] = ("admin", "ADMIN")
                return self.send_json(200, {"token": token})
            if path == "/api/student/claim":
                roll = str(data.get("rollNo", "")).strip().upper()
                name = str(data.get("fullName", "")).strip()
                if not roll or len(name) < 2:
                    return self.send_json(400, {"error": "Enter your roster name and roll number."})
                with connect() as db:
                    row = db.execute("SELECT * FROM roster WHERE roll_no=?", (roll,)).fetchone()
                    if not row or row["full_name"].casefold() != name.casefold():
                        return self.send_json(403, {"error": "Name and roll number do not match an imported college roster row."})
                    student = db.execute("SELECT * FROM students WHERE roll_no=?", (roll,)).fetchone()
                    if not student:
                        if row["claimed"]:
                            return self.send_json(409, {"error": "This roster identity was already claimed. Ask a lecturer to review it."})
                        db.execute("INSERT INTO students(roll_no,full_name) VALUES(?,?)", (roll, row["full_name"]))
                        db.execute("UPDATE roster SET claimed=1 WHERE roll_no=?", (roll,))
                        student = db.execute("SELECT * FROM students WHERE roll_no=?", (roll,)).fetchone()
                token = secrets.token_urlsafe(32)
                tokens[token] = ("student", roll)
                return self.send_json(200, {"token": token, "rollNo": roll, "fullName": student["full_name"],
                    "embedding": json.loads(student["embedding"]) if student["embedding"] else None})
            if path == "/api/student/enrollment":
                role, roll = self.require_token("student")
                vector = embedding_vector(data.get("embedding"))
                with connect() as db:
                    row = db.execute("SELECT embedding FROM students WHERE roll_no=?", (roll,)).fetchone()
                    if not row:
                        return self.send_json(404, {"error": "Student record not found."})
                    if row["embedding"]:
                        return self.send_json(409, {"error": "Face enrollment is locked; submit a change request for lecturer approval."})
                    saved = db.execute("UPDATE students SET embedding=?, enrolled_at=? WHERE roll_no=? AND embedding IS NULL", (json.dumps(vector), int(time.time()*1000), roll))
                    if saved.rowcount != 1:
                        return self.send_json(409, {"error": "Face enrollment was already completed. Submit a change request for lecturer approval."})
                    db.execute("INSERT INTO audit(roll_no,action,details,created_at) VALUES(?,?,?,?)", (roll, "face_enrolled", "Initial face embedding registered", int(time.time()*1000)))
                return self.send_json(200, {"ok": True})
            if path == "/api/student/identity-request":
                _, roll = self.require_token("student")
                requested_roll = str(data.get("rollNo", "")).strip().upper() or None
                requested_name = str(data.get("fullName", "")).strip() or None
                reason = str(data.get("reason", "")).strip()
                vector = embedding_vector(data["embedding"]) if data.get("embedding") else None
                reset_registration = bool(data.get("resetRegistration"))
                if reset_registration and (requested_roll or requested_name or vector):
                    return self.send_json(400, {"error": "A registration reset request cannot include other identity changes."})
                if not reset_registration and not requested_roll and not requested_name and vector is None:
                    return self.send_json(400, {"error": "Include an identity or face change."})
                if len(reason) < 3:
                    return self.send_json(400, {"error": "Please provide a reason for the request."})
                with connect() as db:
                    db.execute("""INSERT INTO change_requests(roll_no,requested_roll_no,requested_name,embedding,reset_registration,reason,created_at)
                        VALUES(?,?,?,?,?,?,?)""", (roll, requested_roll, requested_name, json.dumps(vector) if vector else None,
                        int(reset_registration), reason, int(time.time()*1000)))
                return self.send_json(201, {"ok": True})
            if path == "/api/admin/roster/import":
                self.require_token("admin")
                text = str(data.get("csv", ""))
                reader = csv.DictReader(text.splitlines())
                if not reader.fieldnames or not {"roll_no", "full_name"}.issubset(set(reader.fieldnames)):
                    return self.send_json(400, {"error": "CSV needs columns roll_no,full_name; optional course_code."})
                count = 0
                with connect() as db:
                    for row in reader:
                        roll = row.get("roll_no", "").strip().upper()
                        name = row.get("full_name", "").strip()
                        course = row.get("course_code", "").strip().upper()
                        if roll and len(name) >= 2:
                            db.execute("INSERT INTO roster(roll_no,full_name,course_code) VALUES(?,?,?) ON CONFLICT(roll_no) DO UPDATE SET full_name=excluded.full_name,course_code=excluded.course_code WHERE roster.claimed=0", (roll, name, course))
                            count += 1
                    # Retire untouched starter examples once the lecturer imports
                    # their official roster. Claimed records remain protected.
                    db.execute("DELETE FROM roster WHERE course_code='STARTER' AND claimed=0")
                return self.send_json(200, {"imported": count})
            if path == "/api/admin/courses/import":
                self.require_token("admin")
                reader = csv.DictReader(str(data.get("csv", "")).lstrip("\ufeff").splitlines())
                columns = {field.strip().lower(): field for field in (reader.fieldnames or [])}
                if not {"course_name", "web_app_url"}.issubset(columns):
                    return self.send_json(400, {"error": "CSV needs columns course_name,web_app_url."})
                imported = 0
                with connect() as db:
                    for row in reader:
                        name = str(row.get(columns["course_name"], "")).strip()
                        url = str(row.get(columns["web_app_url"], "")).strip()
                        parsed = urlparse(url)
                        if (not name or parsed.scheme != "https" or parsed.netloc != "script.google.com"
                                or not parsed.path.startswith("/macros/s/") or not parsed.path.endswith("/exec")):
                            continue
                        db.execute("""INSERT INTO course_sheets(course_name,web_app_url) VALUES(?,?)
                            ON CONFLICT(course_name) DO UPDATE SET web_app_url=excluded.web_app_url""", (name, url))
                        imported += 1
                if not imported:
                    return self.send_json(400, {"error": "No valid course rows found. Use HTTPS Apps Script /exec URLs."})
                return self.send_json(200, {"imported": imported})
            if path == "/api/admin/roster/google":
                self.require_token("admin")
                course_name = str(data.get("courseName", "")).strip()
                with connect() as db:
                    web_app_url = course_sheet_url(db, course_name)
                if not web_app_url:
                    return self.send_json(400, {"error": "Choose a configured course first."})
                try:
                    request = urllib.request.Request(
                        web_app_url,
                        data=json.dumps({"action": "getRoster"}).encode("utf-8"),
                        headers={"Content-Type": "application/json"},
                        method="POST",
                    )
                    with urllib.request.urlopen(request, timeout=20) as response:
                        result = json.loads(response.read().decode("utf-8"))
                except (OSError, ValueError, urllib.error.URLError) as error:
                    return self.send_json(502, {"error": f"Could not read the Google Sheet roster: {error}"})
                if not result.get("ok"):
                    return self.send_json(502, {"error": result.get("error", "Google Sheets roster read failed.")})
                students = result.get("students", [])
                if not isinstance(students, list):
                    return self.send_json(502, {"error": "Google Sheets returned an invalid roster."})
                imported = 0
                with connect() as db:
                    for student in students:
                        roll = str(student.get("rollNo", "")).strip().upper()
                        name = str(student.get("name", "")).strip()
                        if roll and len(name) >= 2:
                            db.execute("""INSERT INTO roster(roll_no,full_name,course_code) VALUES(?,?,?)
                                ON CONFLICT(roll_no) DO UPDATE SET full_name=excluded.full_name
                                WHERE roster.claimed=0""", (roll, name, course_name))
                            db.execute("INSERT OR IGNORE INTO course_roster(course_name,roll_no) VALUES(?,?)", (course_name, roll))
                            imported += 1
                    db.execute("DELETE FROM roster WHERE course_code='STARTER' AND claimed=0")
                return self.send_json(200, {"imported": imported})
            if path == "/api/admin/sessions":
                self.require_token("admin")
                course = str(data.get("courseName", "")).strip()
                title = course
                session_type = str(data.get("classType", "")).strip().lower()
                try:
                    duration_hours = float(data.get("durationHours", 0))
                except (TypeError, ValueError):
                    duration_hours = 0
                with connect() as db:
                    if not course_sheet_url(db, course):
                        return self.send_json(400, {"error": "Choose a course with a configured Google Sheets link."})
                if session_type not in ("class", "lab", "tutorial"):
                    return self.send_json(400, {"error": "Choose Class, Lab, or Tutorial."})
                if not 0.25 <= duration_hours <= 12:
                    return self.send_json(400, {"error": "Duration must be between 0.25 and 12 hours."})
                session_id = secrets.token_urlsafe(12)
                now = int(time.time() * 1000)
                with connect() as db:
                    db.execute("INSERT INTO class_sessions(id,course_code,title,started_at,session_type,duration_hours) VALUES(?,?,?,?,?,?)", (session_id, course, title, now, session_type, duration_hours))
                active_sessions[session_id] = {"course": course, "nonce": secrets.randbelow(900_000)+100_000, "ts": now}
                return self.send_json(201, {"id": session_id})
            if path.startswith("/api/admin/requests/"):
                self.require_token("admin")
                request_id = int(path.rsplit("/", 1)[1])
                approve = bool(data.get("approve"))
                with connect() as db:
                    req = db.execute("SELECT * FROM change_requests WHERE id=? AND status='pending'", (request_id,)).fetchone()
                    if not req:
                        return self.send_json(404, {"error": "Request is no longer pending."})
                    revoked_rolls = {req["roll_no"]}
                    if approve:
                        if req["reset_registration"]:
                            roster = db.execute("SELECT 1 FROM roster WHERE roll_no=?", (req["roll_no"],)).fetchone()
                            if not roster:
                                return self.send_json(409, {"error": "The student's row is no longer in the imported roster."})
                            db.execute("UPDATE roster SET claimed=0 WHERE roll_no=?", (req["roll_no"],))
                            db.execute("DELETE FROM students WHERE roll_no=?", (req["roll_no"],))
                            db.execute("UPDATE change_requests SET status='rejected' WHERE roll_no=? AND id<>? AND status='pending'", (req["roll_no"], request_id))
                            db.execute("INSERT INTO audit(roll_no,action,details,created_at) VALUES(?,?,?,?)",
                                (req["roll_no"], "registration_reset_approved", str(request_id), int(time.time()*1000)))
                        else:
                            old_roll = req["roll_no"]
                            new_roll = req["requested_roll_no"] or old_roll
                            current = db.execute("SELECT * FROM students WHERE roll_no=?", (old_roll,)).fetchone()
                            if not current:
                                return self.send_json(404, {"error": "The student record no longer exists."})
                            target_roster = db.execute("SELECT * FROM roster WHERE roll_no=?", (new_roll,)).fetchone()
                            if not target_roster:
                                return self.send_json(409, {"error": "The requested roll number must exist in the imported college roster."})
                            if new_roll != old_roll:
                                target_student = db.execute("SELECT 1 FROM students WHERE roll_no=?", (new_roll,)).fetchone()
                                if target_roster["claimed"] or target_student:
                                    return self.send_json(409, {"error": "The requested roll number is already claimed."})
                                conflict = db.execute("""SELECT 1 FROM attendance old
                                    JOIN attendance new ON new.session_id=old.session_id
                                    WHERE old.roll_no=? AND new.roll_no=? LIMIT 1""", (old_roll, new_roll)).fetchone()
                                if conflict:
                                    return self.send_json(409, {"error": "Both roll numbers already have attendance in the same class; resolve that record before changing the identity."})
                                revoked_rolls.add(new_roll)
                            new_name = req["requested_name"] or (target_roster["full_name"] if new_roll != old_roll else current["full_name"])
                            if req["embedding"]:
                                db.execute("UPDATE students SET roll_no=?,full_name=?,embedding=?,enrolled_at=? WHERE roll_no=?",
                                    (new_roll, new_name, req["embedding"], int(time.time()*1000), old_roll))
                            else:
                                db.execute("UPDATE students SET roll_no=?,full_name=? WHERE roll_no=?", (new_roll, new_name, old_roll))
                            db.execute("UPDATE roster SET claimed=1,full_name=? WHERE roll_no=?", (new_name, new_roll))
                            if new_roll != old_roll:
                                db.execute("""INSERT OR IGNORE INTO course_roster(course_name,roll_no)
                                    SELECT course_name,? FROM course_roster WHERE roll_no=?""", (new_roll, old_roll))
                                db.execute("DELETE FROM course_roster WHERE roll_no=?", (old_roll,))
                                db.execute("DELETE FROM roster WHERE roll_no=?", (old_roll,))
                                db.execute("UPDATE attendance SET roll_no=?,full_name=? WHERE roll_no=?", (new_roll, new_name, old_roll))
                                db.execute("UPDATE change_requests SET status='rejected' WHERE roll_no=? AND id<>? AND status='pending'", (old_roll, request_id))
                            else:
                                db.execute("UPDATE attendance SET full_name=? WHERE roll_no=?", (new_name, old_roll))
                            db.execute("INSERT INTO audit(roll_no,action,details,created_at) VALUES(?,?,?,?)",
                                (new_roll, "identity_change_approved", str(request_id), int(time.time()*1000)))
                    db.execute("UPDATE change_requests SET status=? WHERE id=?", ("approved" if approve else "rejected", request_id))
                for key, value in list(tokens.items()):
                    if approve and value[0] == "student" and value[1] in revoked_rolls:
                        tokens.pop(key, None)
                return self.send_json(200, {"ok": True})
            if path.endswith("/end") and path.startswith("/api/admin/sessions/"):
                self.require_token("admin")
                session_id = path.split("/")[4]
                active_sessions.pop(session_id, None)
                with connect() as db:
                    db.execute("UPDATE class_sessions SET ended_at=? WHERE id=?", (int(time.time()*1000), session_id))
                    session = db.execute("SELECT course_code FROM class_sessions WHERE id=?", (session_id,)).fetchone()
                    configured = bool(session and course_sheet_url(db, session["course_code"]))
                queue_google_sheet_sync(session_id)
                return self.send_json(200, {
                    "ok": True,
                    "sheetSyncQueued": configured,
                })
            if path == "/api/attendance/check-in":
                _, roll = self.require_token("student")
                token = data.get("qr", {})
                session_id = str(token.get("sessionId", ""))
                current = active_sessions.get(session_id)
                now = int(time.time() * 1000)
                if not current or token.get("nonce") != current["nonce"] or token.get("ts") != current["ts"] or now - current["ts"] < 0 or now - current["ts"] > QR_LIFETIME_MS:
                    return self.send_json(409, {"error": "QR code expired or was superseded. Scan the current projector code."})
                vector = embedding_vector(data.get("embedding"))
                with connect() as db:
                    student = db.execute("SELECT full_name,embedding FROM students WHERE roll_no=?", (roll,)).fetchone()
                    if not student or not student["embedding"]:
                        return self.send_json(403, {"error": "Complete face enrollment before checking in."})
                    score = distance(vector, json.loads(student["embedding"]))
                    if score > MATCH_LIMIT:
                        return self.send_json(403, {"error": "Face does not match the registered student."})
                    try:
                        db.execute("INSERT INTO attendance(session_id,roll_no,full_name,checked_in_at,embedding_distance) VALUES(?,?,?,?,?)", (session_id, roll, student["full_name"], now, score))
                    except sqlite3.IntegrityError:
                        return self.send_json(409, {"error": "You already checked in to this class."})
                return self.send_json(201, {"ok": True, "distance": round(score, 4), "checkedInAt": now})
            return self.send_json(404, {"error": "Not found."})
        except PermissionError as error:
            return self.send_json(401, {"error": str(error)})
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
            return self.send_json(400, {"error": str(error)})
        except Exception as error:  # Return a readable local error; details remain in lecturer terminal.
            print(f"[API] Unhandled error on {path}: {error}")
            return self.send_json(500, {"error": "The local attendance server encountered an error."})


def main():
    parser = argparse.ArgumentParser(description="Local classroom attendance server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    initialize()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"[SERVER] Lecturer page/API: http://localhost:{args.port}")
    print("[SERVER] LAN addresses (use one of these in the student app):")
    addresses = set()
    try:
        # A UDP connect selects the active outbound interface without sending
        # traffic, which can reveal Wi-Fi even when hostname lookup is loopback.
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.connect(("192.0.2.1", 80))
            addresses.add(probe.getsockname()[0])
        finally:
            probe.close()
        for result in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = result[4][0]
            if not address.startswith("127."):
                addresses.add(address)
    except OSError:
        pass
    for address in sorted(addresses):
        print(f"[SERVER]   http://{address}:{args.port}/api/health")
    if not addresses:
        print("[SERVER]   Could not detect an address; check Wi-Fi adapter settings.")
    if os.name == "nt":
        print(f"[SERVER] If phones cannot connect, allow inbound TCP port {args.port} "
              "in the Windows Defender Firewall for Private networks.")
    elif sys.platform == "darwin":
        print("[SERVER] If phones cannot connect, allow incoming connections for Python "
              "in macOS Firewall settings.")
    else:
        print(f"[SERVER] If UFW is active and phones cannot connect, run: "
              f"sudo ufw allow {args.port}/tcp")
    print("[SERVER] Set ATTENDANCE_ADMIN_PASSWORD before sharing this server.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[SERVER] Stopping.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
