```markdown
# AI Agent Rules: Attendance Tracking System

## 1. Core Architectural Constraints
* **Zero Heavy Infrastructure:** Strictly avoid Docker containers, Node.js Express servers, local PostgreSQL instances, or local microservices.
* **Backend Platform:** Use managed serverless platforms (Firebase or Supabase). All write validations, session timing rules, and anti-proxy constraints must be enforced via Database Security Rules or Row-Level Security (RLS) policies.
* **Target Platforms:**
  * **Lecturer Interface:** Lightweight Web Application (`index.html` + vanilla JavaScript or Web SDK) optimized for classroom projectors.
  * **Student Interface:** Cross-platform Flutter Mobile Application (`lib/` codebase).

---

## 2. Anti-Proxy & Security Architecture
* **Dynamic Time-Bound QR Codes:**
  * Payload: Minified JSON string `{"session": "CS101", "nonce": 849120, "ts": 1793212800142}`.
  * The projector refreshes the QR code every 2.0 seconds (anti-screenshot / anti-remote-sharing measure).
  * The 2.0-second window is a **projector-side refresh cadence**, student submission deadline is 3 seconds.
  * Replay attacks blocked via server-side unique `nonce` checks per student per session.
* **Verification Order (critical):**
  * **Face liveness (Module 4) → face verification (Module 5) → QR scanning (Module 3).**
  * The student completes liveness with no time pressure. The live face is then matched against the enrolled 128-d embedding (cosine distance `< 0.40`); the QR scanner stays locked until it matches.
  * Only after a MATCH does the student scan whichever QR code is currently on the projector, so the scanned token is always fresh at the moment of scanning.
  * Liveness alone is not enough: the face must also match the enrolled student. The backend re-verifies the identity match and token; a client-side "verified" flag is never trusted.
* **Client-Side Face Liveness (Google ML Kit):**
  * Process camera frames using `google_mlkit_face_detection`.
  * Track active eye-blink probabilities (`leftEyeOpenProbability`, `rightEyeOpenProbability`) and smile probabilities to prevent static photo spoofs.
* **Vector Embedding Extraction (TFLite MobileFaceNet):**
  * Crop the bounding box returned by ML Kit.
  * Pass the 112x112 cropped matrix to `MobileFaceNet.tflite` via `tflite_flutter` to extract a 128-dimensional floating-point array.
  * Send *only* the 128d vector array to the database—never raw face photographs.
* **Hardware Device Binding:**
  * Capture phone hardware UUID using `device_info_plus` to bind a student account to a single physical device.

---

## 3. Modular Development Strategy & Output Rules
When generating code, never produce monolithic full-stack code dumps. Every task must belong to one of the following six independent, self-contained modules. Every module must include its own interactive UI screen with live visual feedback.

```text
lib/
├── features/
│   ├── module_1_auth/       # Standalone Auth Screen & Role Selector
│   ├── module_2_qr_gen/     # Standalone Dynamic QR Generator (Lecturer)
│   ├── module_3_qr_scan/    # Standalone Scanner & Token Inspector (Student)
│   ├── module_4_liveness/   # Standalone ML Kit Liveness Feed & Meter UI
│   ├── module_5_embedding/  # Standalone 128d TFLite Vector Extractor UI
│   └── module_6_sync/       # End-to-End Live Sync Dashboard
```

### Module Specifications

#### Module 1: Standalone Auth & User Context

* **Deliverable:** Flutter UI screen for student login, live form validation styling, and a post-login Interactive Session Card displaying `uid`, role badge, and cryptographic session JWT token.
* **Verification:** Run `flutter run` and interact with forms directly on-screen.

#### Module 2: Standalone Dynamic QR Generator

* **Deliverable:** Standalone web page (`index.html`) or Flutter screen rendering a high-contrast QR code, a 2.0-second circular timer countdown, and a live JSON string inspector showing rotating `ts` and `nonce` values.
* **Verification:** Open in browser or laptop desktop build; observe code morphing every 2000ms.

#### Module 3: Standalone QR Camera Scanner & Inspector

* **Deliverable:** Student camera view (`mobile_scanner`) with an animated viewfinder overlay. Points at any QR code and renders an on-screen Validation Card:
* Green Banner: "Valid Token | Generated 400ms ago"
* Red Banner: "Expired Token | Generated 3.2s ago (Rejected)"


* **Verification:** Scan Module 2 on a laptop screen from a phone.

#### Module 4: Standalone Face Liveness Feed

* **Deliverable:** Camera preview with an oval face frame overlay and live visual meters:
* `Left Eye Open`: 0% to 100% progress bar
* `Right Eye Open`: 0% to 100% progress bar
* `Smile Probability`: 0% to 100% progress bar
* On blink detection, trigger a green screen flash and checkmark animation.


* **Verification:** Test live face vs printed paper photo on phone camera.

#### Module 5: Standalone Vector Extractor & Inspector

* **Deliverable:** Takes a cropped face image, feeds it to `MobileFaceNet.tflite`, and displays a Visual Vector Inspector Grid rendering all 128 floating-point values on-screen. Includes a live cosine distance tool (`Distance < 0.40 = MATCH`).
* **Verification:** Compare two photos on-device without network dependency.

#### Module 6: End-to-End Live Sync

* Deliverable: Connects the Flutter app (Modules 1, 3, 4, 5) and the lecturer web page (Module 2) to Firebase/Supabase. The student's attendance write triggers a real-time listener on the lecturer's web page, which prepends the student to the live roster.
---

## 4. Coding Standards for the Agent

1. **Visual Feedback First:** Do not write headless services or terminal-only unit tests unless paired directly with an on-screen widget that displays state visually.
2. **Verbose Boundary Logging:** Include explicit print statements at all camera, ML, and network boundaries:
```dart
print('[Liveness] Frame processed: LeftEye=\${face.leftEyeOpenProbability}');

```


3. **No Unused Heavy Dependencies:** Stick strictly to `mobile_scanner`, `google_mlkit_face_detection`, `tflite_flutter`, `device_info_plus`, and official Firebase/Supabase SDKs.
