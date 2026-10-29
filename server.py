#!/usr/bin/env python3
"""Local classroom attendance server. Python standard library only."""
from __future__ import annotations

import argparse
import csv
import hmac
import json
import os
import secrets
import socket
import sqlite3
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("ATTENDANCE_DB", ROOT / "data" / "attendance.sqlite3"))
ADMIN_PASSWORD = os.environ.get("ATTENDANCE_ADMIN_PASSWORD", "")
MATCH_LIMIT = 0.90
QR_LIFETIME_MS = 3000
tokens: dict[str, tuple[str, str]] = {}
active_sessions: dict[str, dict] = {}


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
        CREATE TABLE IF NOT EXISTS students (
          roll_no TEXT PRIMARY KEY, full_name TEXT NOT NULL,
          embedding TEXT, enrolled_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS change_requests (
          id INTEGER PRIMARY KEY AUTOINCREMENT, roll_no TEXT NOT NULL,
          requested_roll_no TEXT, requested_name TEXT, embedding TEXT,
          reason TEXT NOT NULL, created_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending'
        );
        CREATE TABLE IF NOT EXISTS audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT, roll_no TEXT NOT NULL,
          action TEXT NOT NULL, details TEXT NOT NULL, created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS class_sessions (
          id TEXT PRIMARY KEY, course_code TEXT NOT NULL, title TEXT NOT NULL,
          started_at INTEGER NOT NULL, ended_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS attendance (
          id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
          roll_no TEXT NOT NULL, full_name TEXT NOT NULL, checked_in_at INTEGER NOT NULL,
          embedding_distance REAL NOT NULL,
          UNIQUE(session_id, roll_no),
          FOREIGN KEY(session_id) REFERENCES class_sessions(id)
        );
        """)
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
        if path in ("/api/admin/requests", "/api/admin/sessions") or (
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
            if now - current["ts"] >= 2000:
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
                if not requested_roll and not requested_name and vector is None:
                    return self.send_json(400, {"error": "Include an identity or face change."})
                if len(reason) < 3:
                    return self.send_json(400, {"error": "Please provide a reason for the request."})
                with connect() as db:
                    db.execute("INSERT INTO change_requests(roll_no,requested_roll_no,requested_name,embedding,reason,created_at) VALUES(?,?,?,?,?,?)",
                        (roll, requested_roll, requested_name, json.dumps(vector) if vector else None, reason, int(time.time()*1000)))
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
                return self.send_json(200, {"imported": count})
            if path == "/api/admin/roster/mock":
                self.require_token("admin")
                with connect() as db:
                    db.executemany(
                        "INSERT INTO roster(roll_no,full_name,course_code) VALUES(?,?,?) ON CONFLICT(roll_no) DO NOTHING",
                        [(f"25BCS{i:03d}", f"Mock Student {i:03d}", "CS101") for i in range(1, 101)],
                    )
                return self.send_json(200, {"created": 100, "firstRollNo": "25BCS001", "lastRollNo": "25BCS100"})
            if path == "/api/admin/sessions":
                self.require_token("admin")
                course = str(data.get("courseCode", "")).strip().upper()
                title = str(data.get("title", "")).strip()
                if not course or not title:
                    return self.send_json(400, {"error": "Course code and class title are required."})
                session_id = secrets.token_urlsafe(12)
                now = int(time.time() * 1000)
                with connect() as db:
                    db.execute("INSERT INTO class_sessions(id,course_code,title,started_at) VALUES(?,?,?,?)", (session_id, course, title, now))
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
                    if approve:
                        new_roll = req["requested_roll_no"] or req["roll_no"]
                        new_name = req["requested_name"]
                        if req["requested_roll_no"] and new_roll != req["roll_no"]:
                            roster = db.execute("SELECT * FROM roster WHERE roll_no=?", (new_roll,)).fetchone()
                            if not roster or roster["claimed"]:
                                return self.send_json(409, {"error": "Requested roll number must be present and unclaimed in the imported roster."})
                            db.execute("UPDATE roster SET claimed=1 WHERE roll_no=?", (new_roll,))
                            db.execute("UPDATE roster SET claimed=0 WHERE roll_no=?", (req["roll_no"],))
                        updates, args = [], []
                        if req["requested_roll_no"]:
                            updates.append("roll_no=?"); args.append(new_roll)
                        if new_name:
                            updates.append("full_name=?"); args.append(new_name)
                        if req["embedding"]:
                            updates.extend(["embedding=?", "enrolled_at=?"]); args.extend([req["embedding"], int(time.time()*1000)])
                        if updates:
                            args.append(req["roll_no"])
                            db.execute("UPDATE students SET " + ",".join(updates) + " WHERE roll_no=?", args)
                        db.execute("INSERT INTO audit(roll_no,action,details,created_at) VALUES(?,?,?,?)", (new_roll, "identity_change_approved", str(request_id), int(time.time()*1000)))
                        if new_roll != req["roll_no"]:
                            db.execute("UPDATE attendance SET roll_no=? WHERE roll_no=?", (new_roll, req["roll_no"]))
                    db.execute("UPDATE change_requests SET status=? WHERE id=?", ("approved" if approve else "rejected", request_id))
                for key, value in list(tokens.items()):
                    if value == ("student", req["roll_no"]):
                        tokens.pop(key, None)
                return self.send_json(200, {"ok": True})
            if path.endswith("/end") and path.startswith("/api/admin/sessions/"):
                self.require_token("admin")
                session_id = path.split("/")[4]
                active_sessions.pop(session_id, None)
                with connect() as db:
                    db.execute("UPDATE class_sessions SET ended_at=? WHERE id=?", (int(time.time()*1000), session_id))
                return self.send_json(200, {"ok": True})
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
