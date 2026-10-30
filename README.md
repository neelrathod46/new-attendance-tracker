# Classroom Attendance

Flutter Android attendance app with a local Python server hosted by the lecturer. The server provides the projector page, roster, identity approvals, time-limited QR tokens, and SQLite attendance records. No Supabase or cloud account is used.

## Start the lecturer server

Python 3.10 or newer is required; the server uses only Python's standard library.

1. Set an administrator password and start the server from the project folder:

   ```bash
   export ATTENDANCE_ADMIN_PASSWORD='choose-a-classroom-password'
   python3 server.py --host 0.0.0.0 --port 8765
   ```

   On Windows PowerShell, use `$env:ATTENDANCE_ADMIN_PASSWORD='choose-a-classroom-password'` before `python server.py --host 0.0.0.0 --port 8765`.
2. Leave that terminal open. Startup prints one or more LAN health-check addresses. Use the address for the Wi-Fi adapter (usually `192.168.x.x` or `10.x.x.x`), not a VPN, Docker, or virtual adapter. On the lecturer laptop, open `http://localhost:8765` in a browser and sign in using the password you set.
3. A starter roster is added once to a new or existing database: Neel Rathod (`25BCS099`) and Sample Student 001–005 (`25BCS001`–`25BCS005`). For a real roster, choose **Fetch roster from Google Sheets** or import a CSV with `roll_no,full_name,course_code` headings. Fetching/importing updates matching unclaimed starter entries and removes the remaining unclaimed starter examples.
4. The server loads course mappings from `courses.csv` in the project folder at startup. Select a course from the dashboard dropdown, choose **Class**, **Lab**, or **Tutorial**, set the class duration in hours, then choose **Start attendance session**. Keep the dashboard open; the QR rotates and check-ins appear in the roster panel.
5. Connect the lecturer laptop and student phones to the same institute Wi-Fi. The Wi-Fi must allow devices to communicate with each other (client isolation must be off).
6. Find the laptop's Wi-Fi IPv4 address:

   - Windows: run `ipconfig` and find **IPv4 Address** under the Wi-Fi adapter.
   - macOS: run `ipconfig getifaddr en0` in Terminal.
   - Linux: run `hostname -I` and use the address for the Wi-Fi network.

   From a phone on that Wi-Fi, open `http://<laptop-ip>:8765/api/health` in its browser, replacing `<laptop-ip>` with that address. It should show a small JSON response containing `"ok":true`.

7. Open the student app. First-time students enter their exact roster name and roll number, then tap **Scan lecturer QR and register**. Scan the registration QR on the dashboard; the QR supplies the laptop's Wi-Fi address. A returning student's saved profile opens directly and shows their name and roll number.
8. Complete **Enroll my face** once. To check in, tap **Verify and check in**, pass liveness and face matching, then scan the live projector QR within one minute. The app reads the server address from the QR and submits automatically. The server confirms the embedding and one-second QR token before recording attendance.
9. At the end of class, choose **End session**. Keep the server terminal and laptop running until everyone has checked in.

## Google Sheets attendance

Attendance always saves to the laptop's SQLite database first. Google Sheets is an optional live copy. Check-ins do not contact Apps Script. When the lecturer ends a session, one request sends only the session date, class type, duration in hours, and roll numbers of students who checked in. The Apps Script uses those roll numbers to fill the duration in matching rows already in the sheet; it does not receive names or the local roster, and it does not append student rows. Absent students' cells remain blank. The first two columns are `Name` and `Roll No`. Each event heading is its date and type, such as `2026-10-30 Class`. The CSV download uses this same wide layout, with one student per row and one session per column. If the update fails, attendance remains in SQLite and the dashboard reports the error.

1. For each course, create or open its Google spreadsheet and copy its ID from the URL (the part between `/d/` and `/edit`). The first tab is used. The sheet needs `Name` and `Roll No` in columns A and B.
2. Create an Apps Script web app for each sheet. Paste in [`google_sheets_apps_script.gs`](google_sheets_apps_script.gs), set `SPREADSHEET_ID` in **Project Settings → Script properties**, then deploy as a web app (execute as you; access for anyone) and copy the URL ending in `/exec`. Each course needs a URL configured for its own spreadsheet.
3. Make a CSV with these exact column headings and one row per course:

   ```csv
   course_name,web_app_url
   Algorithms,https://script.google.com/macros/s/DEPLOYMENT_ID_1/exec
   Physics Lab,https://script.google.com/macros/s/DEPLOYMENT_ID_2/exec
   ```

4. Save this list as `courses.csv` beside `server.py`. The server reads it on startup and adds or updates those course links in its SQLite database. You can also upload the CSV from **Manage courses and Google Sheets** for immediate use; edit `courses.csv` too if the updated links should remain the source of truth after later restarts.
5. Select a course in **Class setup**. **Fetch roster from Google Sheets** reads that course's first two sheet columns. Check-ins save locally during class; ending the session sends its date, session type, duration, and attended roll numbers to that course's sheet. **Export selected course as CSV** downloads a local CSV matching that course's sheet layout.

If you edit an Apps Script later, update its deployment so the `/exec` URL serves the latest code, then keep that URL in the course CSV. Google Sheets sync needs internet on the lecturer laptop; QR check-in and local SQLite recording continue if Sheets is temporarily unavailable.

Students get the lecturer address by scanning the registration QR; they do not type an IP address. For development, you can still set a default server URL when launching the app:

   ```bash
   flutter run --dart-define=ATTENDANCE_SERVER_URL=http://192.168.1.20:8765
   ```

   Replace `192.168.1.20` with the laptop address. For a physical phone, do not use `localhost` (it points to the phone itself) or `10.0.2.2` (Android emulator only).

The lecturer laptop firewall must allow inbound TCP port `8765` on its **Private** network profile. On Windows, open PowerShell as Administrator and run `New-NetFirewallRule -DisplayName "Classroom Attendance LAN" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8765 -Profile Private`. On macOS, allow incoming connections for Python when prompted. Linux users with UFW can run `sudo ufw allow 8765/tcp`. The laptop and phone need to stay on the same network, and the Wi-Fi must allow device-to-device traffic; guest Wi-Fi and institute networks often block this even when both devices have internet. **Do not open `index.html` by double-clicking it, or host only that file on GitHub Pages.** The page and its bundled QR renderer must be served by `server.py` at `http://localhost:8765`; otherwise its `/api/...` requests have nowhere to go. The QR renderer is stored locally, so QR display does not require internet access.

### If it says “Cannot reach local server”

1. On the lecturer laptop, check that the terminal running `python3 server.py --host 0.0.0.0 --port 8765` is still open and has no startup error.
2. On that laptop, open `http://localhost:8765/api/health`. If it fails, restart the server from the project folder.
3. On the phone, open the exact LAN health-check URL printed by the server, e.g. `http://192.168.1.20:8765/api/health`. It must show JSON with `"ok":true` and `"server":"AttendanceLAN/1.0"`. If the laptop's `http://localhost:8765/api/health` works but the phone URL times out, the problem is the laptop firewall or Wi-Fi access-point isolation; changing the app cannot fix that network block. Try a non-guest Wi-Fi network or a phone hotspot with the laptop connected to it.
4. Enter the same laptop IP and port in the app. Do not enter the phone's IP, `localhost`, or `10.0.2.2` on a physical phone.
5. If you reached this app page from a hosted website, that's the issue: the hosted page cannot access a server running on the laptop. Open `http://localhost:8765` on the lecturer laptop instead.

## Student flow

- The lecturer imports the official roster. A student enters the exact roster name and roll number to claim their row. A claimed identity cannot be claimed again.
- The student completes liveness and face enrollment. Only the 192-value MobileFaceNet embedding is sent to the lecturer server; the captured face image is deleted locally.
- The enrolled roll number and face are locked. Students can request name, roll, or face corrections; the lecturer reviews these in the dashboard.
- A student can request a registration reset in the app; it takes effect only after lecturer approval. Approval releases the roster claim and removes the saved face vector while retaining past attendance.
- Attendance requires liveness, a matching enrolled face, and a current projector QR token. The app submits automatically after a valid scan. The lecturer server rotates tokens every second and rejects check-ins if the token is over one second old; it also repeats the embedding match before recording one attendance row per student per class session.
- The **Continue offline demo** button only exercises the local camera/face/QR flow. It does not write attendance.

The server rejects a first-time name/roll pair unless it matches an unclaimed row in the lecturer's imported roster. For stronger identity assurance, have the lecturer verify each student in person before their first claim, or add a one-time registration code delivered privately to that student. A name and roll number alone can still be copied by someone who knows another student's unclaimed roster details.

## Data and backups

SQLite data is saved to `data/attendance.sqlite3` beside the server. Copy that file to make a backup while the server is stopped. Do not delete it between classes unless you intend to reset roster claims, face registrations, approvals, and attendance.

The server binds to the local network and uses HTTP. This is a classroom prototype for a trusted institute network, not a hardened internet-facing service. Keep it off public networks and use a strong administrator password.

## App development

```bash
flutter pub get
flutter analyze
flutter run --dart-define=ATTENDANCE_SERVER_URL=http://192.168.1.20:8765
```

The GitHub Actions workflow builds a debug APK. The QR scanner is only reachable after local liveness and face matching succeed.
