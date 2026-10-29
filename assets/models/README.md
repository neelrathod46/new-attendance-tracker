# Supplied MobileFaceNet model

The app loads `assets/mobile_face_net.tflite`, the model copied into this project
from [Mahesh-R-Mesta/Image-recognition-app](https://github.com/Mahesh-R-Mesta/Image-recognition-app/tree/main).
That project's README/article documents a 112×112 RGB input and a 192-value
facial vector. `pubspec.yaml` includes this file as a Flutter asset.

The embedding service prepares the ML Kit face bounding-box crop as follows:

- Resize to 112×112 pixels.
- Use RGB channels in `[0, 255]` and normalize each channel with
  `(pixel - 127.5) / 128`.
- Keep its 192-value output unnormalized and compare with Euclidean distance,
  matching the source app's documented approach.

At load time, the app checks that input is `[1,112,112,3]` and output is
`[1,192]`. If either differs, verification fails with an explicit model-contract
error instead of silently using a wrong output buffer.

The client gate currently uses Euclidean distance `<= 0.90`, following the
source app's example threshold. Calibrate the threshold with representative
enrollment/check-in captures before using this as a real identity decision; this
prototype threshold is not a security guarantee.

The upstream repository does not show a clear model license in its top-level
files. Confirm that the model weights may be redistributed and used for this
project before publishing the APK or repository.
