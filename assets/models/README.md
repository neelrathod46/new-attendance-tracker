# MobileFaceNet model required

Place the approved, licensed MobileFaceNet TensorFlow Lite model at
`assets/models/mobilefacenet.tflite`, then add the following under the existing
`flutter:` key in `pubspec.yaml`:

```yaml
  assets:
    - assets/models/mobilefacenet.tflite
```

The expected model contract is a `float32 [1,112,112,3]` RGB input normalized by
`(pixel - 127.5) / 128`, with a `float32 [1,128]` embedding output. Do not replace
this file with a model whose enrollment vectors were generated under a different
preprocessing contract.
