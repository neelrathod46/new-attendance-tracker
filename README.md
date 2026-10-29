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
3. Expand **Import your student roster**. For a quick trial, choose **Add 100 mock students**. This inserts `Mock Student 001` through `Mock Student 100`, with roll numbers `25BCS001` through `25BCS100` and course `CS101`. For real classes, instead paste a CSV with `roll_no,full_name,course_code` headings into the roster box and import it. Do not use mock names for real attendance.
4. Enter a course code and class title, then choose **Start attendance session**. Keep the dashboard open; the QR rotates and check-ins appear in the roster panel.
5. Connect the lecturer laptop and student phones to the same institute Wi-Fi. The Wi-Fi must allow devices to communicate with each other (client isolation must be off).
6. Find the laptop's Wi-Fi IPv4 address:

   - Windows: run `ipconfig` and find **IPv4 Address** under the Wi-Fi adapter.
   - macOS: run `ipconfig getifaddr en0` in Terminal.
   - Linux: run `hostname -I` and use the address for the Wi-Fi network.

   From a phone on that Wi-Fi, open `http://<laptop-ip>:8765/api/health` in its browser, replacing `<laptop-ip>` with that address. It should show a small JSON response containing `"ok":true`.

7. Open the attendance app on each student phone. In **Lecturer laptop server address**, enter the Wi-Fi URL printed in the lecturer terminal, without `/api/health` (for example `http://192.168.1.20:8765`). APKs for physical phones do not assume an emulator address. Then enter the student's exact roster name and roll number and choose **Register / claim roster identity**. A returning student uses **Sign in** with the same name and roll number.
8. Complete **Enroll face** once. For check-in, complete the liveness/face verification flow and scan the currently displayed QR. Tap **Submit attendance**. The server confirms the embedding and token before adding the student to the lecturer's live roster.
9. At the end of class, choose **End session**. Keep the server terminal and laptop running until everyone has checked in.

The student app has a **Lecturer laptop server address** field, so you can enter the laptop IP there without rebuilding the APK. For development from a connected phone, you can also provide the address when launching the app:

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
- Attendance requires liveness, a matching enrolled face, and a current projector QR token. The server checks the token age/nonce and repeats the embedding match before recording one attendance row per student per class session.
- The **Continue offline demo** button only exercises the local camera/face/QR flow. It does not write attendance.

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
