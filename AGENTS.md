# AGENTS.md

Student attendance system: a Flutter Android app for students plus a standalone
lecturer web page. This file is the authoritative project spec; it inlines the rules
from `.gemini/rules/attendance_rules.md` and adds verified repo facts. Where the two
disagree, this file wins. `README.md` is empty.

## Commands

- `flutter pub get`
- `flutter analyze` — currently clean. Excludes `build/**` and `android/**`;
  `deprecated_member_use` is globally ignored; `avoid_print` is disabled on purpose.
- `flutter test` — 4 unit tests in `test/widget_test.dart`. Despite the filename they
  test `QrPayload`, not widgets.
- Single test: `flutter test test/widget_test.dart --plain-name 'Replay attack'`
- `flutter run` / `flutter build apk --debug` — Android only; no ios/web/desktop
  platform directories exist. By default the app starts on Module 3's locked screen.
- `flutter run --dart-define=BYPASS_FACE_VERIFICATION=true` — debug-only stand-in
  verification so Module 3 can be exercised before Modules 4/5 exist. Release builds
  ignore it and always start locked.
- CI (`.github/workflows/build.yml`) builds a debug APK on every push and uploads an
  artifact. It does not run analyze or tests; run them locally first.

## Environment

- Flutter 3.47.8 / Dart 3.13.7 at `/mnt/work/tools/flutter`; Android SDK at
  `/mnt/work/tools/android-sdk`; pub/gradle caches on `/mnt/work`.
  See `FLUTTER_SETUP_MANUAL.md`. Don't move SDKs or caches to `~` or system dirs.
- Python utilities target 3.12 (`.python-version`); no requirements file exists.

## Repo layout and entrypoints

- `lib/main.dart` → `QrScannerScreen` (Module 3) is currently the only screen. It
  accepts an optional `FaceVerificationResult`; without a fresh passed result the
  screen renders locked and never initializes the camera. New work must slot into the
  mandated feature layout below.
- Theme: dark slate (`0xFF0F172A` background, `0xFF1E293B` surfaces) with sky-blue
  `0xFF38BDF8` and green `0xFF22C55E` accents. Match it in new UI.
- Feature layout is mandated: `lib/features/module_{1_auth,2_qr_gen,3_qr_scan,
  4_liveness,5_embedding,6_sync}/`. Only `module_3_qr_scan/` exists.
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
  The Modules 4/5 screens that produce that result do not exist yet.
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
- Device binding: `device_info_plus` hardware UUID; one student account ↔ one phone.

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
  Firebase/Supabase SDKs. Only `mobile_scanner` is in `pubspec.yaml` today.

## QR token contract (as implemented)

- Validation lives in `lib/features/module_3_qr_scan/models/qr_payload.dart`.
  It rejects non-JSON, missing or non-positive `session`/`nonce`/`ts`, reused nonces,
  codes at or below the newest accepted `ts` (`staleToken`), timestamps more than
  1500 ms in the future, and age > 3000 ms.
- Tests inject time via `QrPayload.parse(..., mockCurrentTimeMs:)`; add cases there
  instead of widget-testing the camera.
- `TokenValidationCard` shows a 3.00 s meter and only offers "Scan Again" — there is
  no post-scan liveness CTA. `QrScannerScreen` advances the newest-`ts` watermark only
  when a token validates.

## Known inconsistencies (confirm before changing behavior)

- Order: Module 3 is now gated and no longer offers a liveness CTA, but the producing
  Modules 4/5 do not exist. `main.dart` therefore starts locked unless the debug
  bypass flag is set.
- Replay: spec requires server-side nonce checks; Module 3 only has an in-memory
  nonce set plus a newest-`ts` watermark.
- Time source: `ts` comes from the lecturer browser clock and is compared against the
  student phone clock; no server-authoritative time yet.
- `.gemini/rules/attendance_rules.md` has uncommitted edits on `main` (now including
  the face-verification gate). `git show HEAD:.gemini/rules/attendance_rules.md`
  still says "hard limit of 2.0 seconds" and has no verification gate. Check
  `git diff` before trusting the committed version.
