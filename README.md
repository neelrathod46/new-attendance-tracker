# Student Attendance Prototype

Flutter Android app for an offline student check-in demo, plus `index.html`, a
standalone lecturer page that rotates a classroom QR code every two seconds.

## Offline student flow

1. Open the app and choose **Continue offline** or **Skip Supabase sign-in**.
   Enter any student ID with at least three characters.
2. Choose **Enroll face** and follow the live open-eyes, blink, reopen, and smile
   prompts. Review the 128-value embedding and save it locally in the current app
   session.
3. Choose **Check in**, pass the same liveness prompts, and wait for the local
   face comparison to show MATCH.
4. Scan the current QR code from `index.html`.
5. A valid QR can be locally checked. Choose **Skip roster submit** to finish
   without sending attendance to a backend.

## Requirements for real face matching

The MobileFaceNet model is not included in this repository. Obtain a properly
licensed TFLite model with the input/output contract documented in
[`assets/models/README.md`](assets/models/README.md), place it at
`assets/models/mobilefacenet.tflite`, then declare it under `flutter.assets` in
`pubspec.yaml`. Without that model, the app intentionally reports the missing
asset and does not unlock the QR scanner.

Enrollment and the generated session exist only in memory. Restarting the app
clears them and requires a new offline login and enrollment. Face images are
temporary and deleted after embedding generation; the vector is kept on device
for the active session.

## Run

```sh
flutter pub get
flutter analyze
flutter run
```

Use a physical Android phone for camera and TFLite behavior. On a laptop, open
`index.html` in a browser and display the QR page to the phone. Keep the phone and
laptop clocks synchronized; tokens older than three seconds are rejected.

## What offline mode does not do

The login, role, device display, and session token are demo values. The app does
not authenticate a user, persist enrollment, submit attendance, or update a live
roster. The QR validation and replay checks are local client-side checks, not a
server security boundary. Supabase integration is a separate future step.
