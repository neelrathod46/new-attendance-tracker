# Project instructions

Student attendance system: Flutter Android student app plus a lecturer dashboard served locally from the lecturer laptop. The laptop server is Python standard library + SQLite; no Docker, Node, cloud backend, Supabase, or Firebase.

## Commands and environment

- `flutter pub get`, `flutter analyze`, `flutter test`
- `flutter run --dart-define=ATTENDANCE_SERVER_URL=http://<lecturer-laptop-ip>:8765`
- `python3 server.py --host 0.0.0.0 --port 8765`
- Python 3.10+; no Python dependencies. SQLite database is `data/attendance.sqlite3`.
- GitHub Actions builds the Android debug APK.

## Main flow

- `lib/main.dart` starts the student app at `lib/features/module_1_auth/screens/auth_screen.dart`.
- `server.py` serves `index.html` and `/api/...` routes from one process. It stores roster claims, face vectors, approval requests, class sessions, and check-ins in SQLite.
- `index.html` is the lecturer interface for importing a CSV roster, starting/ending a class, presenting the rotating QR, reviewing identity changes, and watching submitted attendance.
- `lib/features/module_1_auth/services/local_attendance_api.dart` is the app's LAN API client. Students can set the lecturer address in the app; `ATTENDANCE_SERVER_URL` provides a build/run default.
- Student identity must match the lecturer-imported roster. The first face embedding is locked; later identity or face changes require lecturer approval.
- The offline demo remains in-memory and does not create attendance records.

## Verification rules

1. Module 4 liveness runs before Module 5 face verification.
2. Enrollment and matching use `assets/mobile_face_net.tflite` (192 values). The student camera capture is processed on device; send only the embedding to the laptop server.
3. Module 3 QR scanner is available only after a fresh successful face match (Euclidean distance <= 0.90).
4. Attendance submissions include the QR token and current face embedding. `server.py` checks the current nonce, 3-second token age, one check-in per student/session, and the embedding match again before writing a row.
5. Local client checks are for experience; server checks decide whether attendance is recorded. Keep the lecturer service on a trusted private network. It currently uses HTTP and is not for internet exposure.

## Product and code conventions

- Keep the dark slate theme (`0xFF0F172A`), surfaces (`0xFF1E293B`), sky blue (`0xFF38BDF8`), and green (`0xFF22C55E`).
- Feature modules live under `lib/features/module_{1_auth,2_qr_gen,3_qr_scan,4_liveness,5_embedding,6_sync}/`.
- Show useful visible feedback for user-facing features. Log camera, ML, and network boundaries with tags such as `[QR_SCAN]`.
- Liveness signals are prototype heuristics, not production anti-spoof protection. Confirm the model weights' license before redistributing.

## Known limits

- Lecturer dashboard serves its bundled QRCode.js renderer from `assets/qrcode.min.js`; `assets/QRCODEJS_LICENSE.txt` contains its MIT license. QR rendering itself works without internet.
- Tokens use the lecturer laptop's clock. Student devices with substantially incorrect clocks may reject a QR before server submission.
- SQLite is stored on the lecturer laptop and has no automatic remote backup or multi-lecturer synchronization.
- Course rosters are imported and a lecturer starts a course session manually; the server does not yet enforce per-course enrollment membership.
- The lecturer page has a **Demo** action that seeds `Mock Student 001`–`Mock Student 100` with roll numbers `25BCS001`–`25BCS100` for local trials.
