# Project instructions

Student attendance system: Flutter Android student app plus a lecturer dashboard served locally from the lecturer laptop. The laptop server is Python standard library + SQLite. Optional Google Sheets copying uses the included Google Apps Script web app; no Docker, Node, Supabase, or Firebase.

## Commands and environment

- `flutter pub get`, `flutter analyze`, `flutter test`
- `flutter run --dart-define=ATTENDANCE_SERVER_URL=http://<lecturer-laptop-ip>:8765`
- `python3 server.py --host 0.0.0.0 --port 8765`
- Python 3.10+; no Python dependencies. SQLite database is `data/attendance.sqlite3`.
- GitHub Actions builds the Android debug APK.

## Main flow

- `lib/main.dart` starts the student app at `lib/features/module_1_auth/screens/auth_screen.dart`.
- `server.py` serves `index.html` and `/api/...` routes from one process. It stores roster claims, face vectors, approval requests, class sessions, and check-ins in SQLite.
- `courses.csv` maps course names to Apps Script web app URLs and is imported at server startup. Lecturers can also upload the file through the dashboard. `google_sheets_apps_script.gs` is the optional Google Sheets reader/writer. Roster fetches happen on lecturer request; attendance sync happens once to the selected course's sheet when a class session ends.
- `index.html` is the lecturer interface for importing a CSV roster, starting/ending a class, presenting the rotating QR, reviewing identity changes, and watching submitted attendance.
- `lib/features/module_1_auth/services/local_attendance_api.dart` is the app's LAN API client. Students can set the lecturer address in the app; `ATTENDANCE_SERVER_URL` provides a build/run default.
- Student identity must match the lecturer-imported roster. The first face embedding is locked; later identity or face changes require lecturer approval.
- A registration reset is requested in the app and only applied after lecturer approval; approval removes the face vector and releases the roster claim while preserving attendance history.
- The offline demo remains in-memory and does not create attendance records.

## Verification rules

1. Module 4 liveness runs before Module 5 face verification.
2. Enrollment and matching use `assets/mobile_face_net.tflite` (192 values). The student camera capture is processed on device; send only the embedding to the laptop server.
3. Module 3 QR scanner is available only after a fresh successful face match (Euclidean distance <= 0.90); that verification expires after one minute.
4. Attendance submissions include the QR token, student roll number, and current face embedding. `server.py` checks the current nonce, one-second token age, one check-in per student/session, and the embedding match again before writing a row. A valid scan submits automatically. The QR includes the lecturer server URL so students do not type it.
5. Local client checks are for experience; server checks decide whether attendance is recorded. Keep the lecturer service on a trusted private network. It currently uses HTTP and is not for internet exposure.

## Product and code conventions

- Keep the dark slate theme (`0xFF0F172A`), surfaces (`0xFF1E293B`), sky blue (`0xFF38BDF8`), and green (`0xFF22C55E`).
- Feature modules live under `lib/features/module_{1_auth,2_qr_gen,3_qr_scan,4_liveness,5_embedding,6_sync}/`.
- Show useful visible feedback for user-facing features. Log camera, ML, and network boundaries with tags such as `[QR_SCAN]`.
- Liveness signals are prototype heuristics, not production anti-spoof protection. Confirm the model weights' license before redistributing.

## Known limits

- Lecturer dashboard serves its bundled QRCode.js renderer from `assets/qrcode.min.js`; `assets/QRCODEJS_LICENSE.txt` contains its MIT license. QR rendering itself works without internet.
- Tokens use the lecturer laptop's clock. Student devices with substantially incorrect clocks may reject a QR before server submission.
- Returning student profiles and face embeddings are stored encrypted with Android Keystore. The dashboard's static QR supports first-time registration, and the rotating class QR carries the same server address for check-in.
- SQLite is stored on the lecturer laptop and has no automatic remote backup or multi-lecturer synchronization.
- Course rosters are imported and a lecturer starts a course session manually; the server does not yet enforce per-course enrollment membership.
- A first-time roster claim proves the submitted name/roll pair matches an unclaimed row, but not that the claimant is the student. Recommend in-person verification or a private one-time enrollment code for stronger initial identity assurance.
- SQLite remains the attendance source of truth. Google Sheets sync is an optional copy and requires internet from the lecturer laptop; a failed sync can be retried from the dashboard.
- Each class session records Class/Lab/Tutorial type and duration in hours. A successful check-in contributes the full configured session duration in its Google Sheets cell; absent students remain blank.
- The lecturer page can fetch the roster from the first two columns of the configured Google Sheet. A starter roster containing Neel Rathod (`25BCS099`) and sample students is seeded once for local trials.
