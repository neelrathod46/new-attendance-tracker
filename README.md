# Student Attendance

Flutter Android student app with a standalone lecturer page. Supabase now backs
email/password sign-in, college-roster identity claims, initial face enrollment,
and admin-approved identity changes.

## Student identity flow

1. A college administrator loads students' official names, roll numbers, and
   college email addresses into `student_roster`.
2. A student creates an account and confirms their college email if prompted.
   Their name and roll number must match the unclaimed roster row assigned to
   that email.
3. The student completes on-device liveness and face enrollment. Only the
   192-value MobileFaceNet embedding is uploaded; the captured image is deleted.
4. The active roll number and face cannot be changed by the student. Requests
   for a name, roll-number, or face change require administrator approval and
   are recorded in an audit table.

The one-time setup steps are in [SUPABASE_SETUP.md](SUPABASE_SETUP.md). The
project URL and publishable key are configured in
`lib/features/module_1_auth/services/supabase_client.dart`; they may be replaced
with `--dart-define` values. Never put a service-role key in the app.

## Offline demo and remaining work

The **Continue offline demo** path still exercises the local camera, liveness,
embedding, and QR UI without claiming a roster entry. QR validation is still
local. Course rosters, lecturer-managed sessions, server-side QR validation,
attendance submission, and live lecturer roster updates are not yet connected
to Supabase.

The supplied model is `assets/mobile_face_net.tflite`; it returns a 192-value
embedding. See [assets/models/README.md](assets/models/README.md) for its model
contract and attribution notes.

## Run

```sh
flutter pub get
flutter run
```

Use a physical Android device to evaluate camera and TFLite inference. See
[SUPABASE_SETUP.md](SUPABASE_SETUP.md) to apply the migration, seed an admin,
load the initial roster, and configure Supabase Auth.
