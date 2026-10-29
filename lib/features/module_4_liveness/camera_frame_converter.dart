import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Converts the Android camera plugin's NV21 frames to ML Kit input.
/// Unsupported formats fail visibly rather than processing incorrectly.
InputImage cameraFrameToInputImage(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation deviceOrientation,
) {
  final rotationDegrees = _rotationDegrees(
    camera.sensorOrientation,
    deviceOrientation,
    camera.lensDirection,
  );
  final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
  if (rotation == null) {
    throw StateError('Unsupported camera rotation: $rotationDegrees degrees.');
  }
  if (image.format.group != ImageFormatGroup.nv21 || image.planes.length != 1) {
    throw StateError(
      'Expected one-plane NV21 camera input; received '
      '${image.format.group} with ${image.planes.length} planes.',
    );
  }
  final plane = image.planes.single;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

int _rotationDegrees(
  int sensorOrientation,
  DeviceOrientation deviceOrientation,
  CameraLensDirection lensDirection,
) {
  final deviceDegrees = switch (deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return lensDirection == CameraLensDirection.front
      ? (sensorOrientation + deviceDegrees) % 360
      : (sensorOrientation - deviceDegrees + 360) % 360;
}
