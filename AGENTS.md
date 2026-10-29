# AGENTS.md

Student attendance system: a Flutter Android app for students plus a standalone
lecturer web page. This file is the authoritative project spec; it inlines the rules
from `.gemini/rules/attendance_rules.md` and adds verified repo facts. Where the two
disagree, this file wins. `README.md` is empty.

## Commands

- `flutter pub get`
- `flutter analyze` — currently clean. Excludes `build/**` and `android/**`;
  `deprecated_member_use` is globally ignored; `avoid_print` is disabled on purpose.
- `flutter test` — unit tests cover QR validation, face-gate rules, embedding math,
  and offline auth/session validation. They do not exercise camera hardware or TFLite.
- Single test: `flutter test test/widget_test.dart --plain-name 'Replay attack'`
- `flutter run` / `flutter build apk --debug` — Android only; no ios/web/desktop
  platform directories exist. The app starts at local student login. QR scanning is
  gated on liveness and a real on-device face match; there is no face bypass.
- CI (`.github/workflows/build.yml`) builds a debug APK on every push and uploads an
  artifact. It does not run analyze or tests; run them locally first.

## Environment

- Flutter 3.47.8 / Dart 3.13.7 at `/mnt/work/tools/flutter`; Android SDK at
  `/mnt/work/tools/android-sdk`; pub/gradle caches on `/mnt/work`.
  See `FLUTTER_SETUP_MANUAL.md`. Don't move SDKs or caches to `~` or system dirs.
- Python utilities target 3.12 (`.python-version`); no requirements file exists.

## Repo layout and entrypoints

- `lib/main.dart` → Module 1 local login. The offline session leads through Module 4
  liveness, Module 5 local embedding verification, and Module 3 QR scanning.
- Offline login/session and face enrollment are mock, in-memory data. The shown token
  is not an authentication JWT, and device display data is not persistent binding.
- Theme: dark slate (`0xFF0F172A` background, `0xFF1E293B` surfaces) with sky-blue
  `0xFF38BDF8` and green `0xFF22C55E` accents. Match it in new UI.
- Feature layout is mandated: `lib/features/module_{1_auth,2_qr_gen,3_qr_scan,
  4_liveness,5_embedding,6_sync}/`. Initial offline implementations exist for Modules
  1, 3, 4 and 5. Modules 2 and 6 are not implemented in Flutter.
- `index.html` is the lecturer projector page: plain HTML/JS, no build step,
  `qrcodejs` from CDN, QR regenerated every 2000 ms, fake check-ins every 4 s.
- `moire_detection.py` is a standalone OpenCV screen-recapture check
  (`python3 moire_detection.py`, reads `test_scan.jpg`). Its deps (`cv2`, `numpy`)
  are not declared anywhere.

## Non-negotiable product rules

### Infrastructure

- No Docker, Node/Express, local Postgres, or local microservices.
- Backend must be managed serverless: Firebase or Supabase. All write validation,
  session timing, and anti-proxy constraints belong in DB security rules / RLS,
  not in the client.
- Lecturer interface: lightweight web app (`index.html` + vanilla JS or Web SDK)
  optimized for classroom projectors.
- Student interface: the Flutter app in `lib/`.

### Verification flow (critical)

The student must pass identity checks **before** the QR scanner is usable:

1. **Face liveness (Module 4)** — untimed. Camera frames are processed with
   `google_mlkit_face_detection`; track left/right eye-open and smile probabilities
   to reject static photos and pre-recorded video.
2. **Face verification (Module 5)** — after liveness passes, crop the ML Kit bounding
   box, resize to 112×112, run `MobileFaceNet.tflite` via `tflite_flutter` to get a
   128-d vector, and compare it with the student's enrolled vector. Cosine distance
   `< 0.40` = MATCH.
3. **QR scan (Module 3)** — only reachable after face verification returns MATCH.
   The student then scans whichever code is currently on the projector.
4. **Submit** the QR token together with the verification result; the backend
   re-validates identity match, nonce, and token age.

- Liveness alone is not sufficient: a live face must also match the enrolled student.
- The QR scanner must not be reachable until verification succeeds. Do not add a
  release-mode bypass. The token simulator in the scanner is debug-only.
- Module 3 enforces this today: `QrScannerScreen` requires a fresh
  `FaceVerificationResult` (liveness passed, identity matched, cosine `< 0.40`,
  issued within the last 5 minutes) and does not initialize the camera otherwise.
  Modules 4/5 produce this result locally; no face-verification bypass exists.
- Real enrollment and matching require the licensed `assets/models/mobilefacenet.tflite`
  described by `assets/models/README.md`. It is not committed. Until it is supplied,
  Module 5 shows an error and the scanner remains gated.
- Liveness uses local eye/blink/smile signals as a prototype heuristic, not as
  production anti-spoof protection.
- Client-side gating is UX; the backend must re-verify the embedding match and the
  QR token. Never trust a client "verified" flag.

### Anti-proxy and security

- Dynamic time-bound QR payload: minified JSON
  `{"session":"CS101","nonce":849120,"ts":1793212800142}`; `ts` is Unix ms.
- Projector refreshes the QR every 2.0 s. The student submission deadline is 3 s.
- Replay attacks are blocked server-side: a nonce is unique per student per session,
  and only the newest nonce issued for the session should be accepted. Module 3 now
  tracks used nonces plus the newest accepted `ts` and rejects superseded codes, but
  this remains a client-side UX check and is bypassable.
- Send only the 128-d embedding vector to the backend — never raw face images.
- Device binding: the offline demo shows Android build information only. A future
  online implementation must use a persistent installation UUID; build ids are not
  unique hardware UUIDs.

### Modules

1. Auth — student login, live validation styling, session card with `uid`, role, JWT.
2. QR generator — high-contrast QR, 2.0 s countdown, live JSON inspector.
3. QR scanner — `mobile_scanner` camera, animated viewfinder, green/red validation
   card showing token age ("Valid Token | Generated 400ms ago").
4. Liveness — camera preview, oval face frame, eye/smile meters, blink success flash.
5. Embedding/verification — 128-d vector grid inspector, cosine-distance tool, and
   the MATCH/NO MATCH gate that unlocks scanning.
6. Sync — student write triggers a realtime roster prepend on the lecturer page.

### Coding standards

- Visual feedback first: every change ships an on-screen widget. No headless
  services or terminal-only tests unless paired with visible UI.
- Log every camera, ML, and network boundary with `print('[Tag] ...')`
  (e.g. `[QR_SCAN]`). This is why `avoid_print` is off.
- No unused heavy dependencies. Allowed: `mobile_scanner`,
  `google_mlkit_face_detection`, `tflite_flutter`, `device_info_plus`, official
  Firebase/Supabase SDKs. `camera`, ML Kit, TFLite, `image`, `mobile_scanner`, and
  `device_info_plus` are currently declared.

## QR token contract (as implemented)

- Validation lives in `lib/features/module_3_qr_scan/models/qr_payload.dart`.
  It rejects non-JSON, missing or non-positive `session`/`nonce`/`ts`, reused nonces,
  codes at or below the newest accepted `ts` (`staleToken`), timestamps more than
  1500 ms in the future, and age > 3000 ms.
- Tests inject time via `QrPayload.parse(..., mockCurrentTimeMs:)`; add cases there
  instead of widget-testing the camera.
- `TokenValidationCard` shows a 3.00 s meter and, for a valid token, offers a button
  to skip the future online roster submission. The offline flow ends after local QR
  validation; it does not create or sync an attendance record.

## Known inconsistencies (confirm before changing behavior)

- Offline flow: local login/session and Modules 4/5 have initial implementations, but
  a real end-to-end run requires the MobileFaceNet asset and physical-device checks
  for camera streaming and inference.
- Replay: spec requires server-side nonce checks; Module 3 only has an in-memory
  nonce set plus a newest-`ts` watermark.
- Time source: `ts` comes from the lecturer browser clock and is compared against the
  student phone clock; no server-authoritative time yet.
- `.gemini/rules/attendance_rules.md` has uncommitted edits on `main` (now including
  the face-verification gate). `git show HEAD:.gemini/rules/attendance_rules.md`
  still says "hard limit of 2.0 seconds" and has no verification gate. Check
  `git diff` before trusting the committed version.
