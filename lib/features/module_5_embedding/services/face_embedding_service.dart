import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../module_4_liveness/models/liveness_result.dart';

/// Runs the project's MobileFaceNet model and compares 128-d embeddings.
///
/// The model must be bundled at [modelAsset]. This service intentionally has
/// no fallback vector: a missing model must leave attendance locked.
class FaceEmbeddingService {
  static const modelAsset = 'assets/models/mobilefacenet.tflite';
  Interpreter? _interpreter;

  Future<List<double>> createEmbedding(LivenessResult liveness) async {
    try {
      _interpreter ??= await Interpreter.fromAsset(modelAsset);
    } catch (_) {
      throw StateError(
        'MobileFaceNet model missing. Add $modelAsset and declare it in pubspec.yaml.',
      );
    }

    final bytes = await File(liveness.imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Could not decode the captured face image.');
    }
    // ML Kit evaluates the camera image in its display orientation. Normalize
    // the JPEG's EXIF rotation before applying those face coordinates.
    final source = img.bakeOrientation(decoded);

    final bounds = liveness.faceBounds;
    final left = bounds.left.round().clamp(0, source.width - 1).toInt();
    final top = bounds.top.round().clamp(0, source.height - 1).toInt();
    final right = (bounds.left + bounds.width)
        .round()
        .clamp(left + 1, source.width)
        .toInt();
    final bottom = (bounds.top + bounds.height)
        .round()
        .clamp(top + 1, source.height)
        .toInt();
    // Crop the ML Kit bounding box before inference. Raw face pixels remain on
    // the device and are never included in the attendance submission.
    final face = img.copyResize(
      img.copyCrop(
        source,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      ),
      width: 112,
      height: 112,
    );
    final input = [
      List.generate(
        112,
        (y) => List.generate(112, (x) {
          final pixel = face.getPixel(x, y);
          return [
            (pixel.r - 127.5) / 128.0,
            (pixel.g - 127.5) / 128.0,
            (pixel.b - 127.5) / 128.0,
          ];
        }),
      ),
    ];
    final output = [List<double>.filled(128, 0)];
    _interpreter!.run(input, output);
    return _l2Normalize(output.first);
  }

  /// Cosine distance. A lower value is a closer identity match.
  static double cosineDistance(List<double> a, List<double> b) {
    if (a.length != 128 || b.length != 128) {
      throw ArgumentError('Both face embeddings must contain 128 values.');
    }
    var dot = 0.0;
    var magnitudeA = 0.0;
    var magnitudeB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magnitudeA += a[i] * a[i];
      magnitudeB += b[i] * b[i];
    }
    if (magnitudeA == 0 || magnitudeB == 0) return double.infinity;
    return 1 - dot / math.sqrt(magnitudeA * magnitudeB);
  }

  static List<double> _l2Normalize(List<double> values) {
    final magnitude = math.sqrt(
      values.fold(0.0, (sum, value) => sum + value * value),
    );
    if (magnitude == 0) {
      throw StateError('The model returned an empty embedding.');
    }
    return values.map((value) => value / magnitude).toList(growable: false);
  }

  void dispose() {
    _interpreter?.close();
  }
}
