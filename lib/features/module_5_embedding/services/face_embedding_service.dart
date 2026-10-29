import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../module_4_liveness/models/liveness_result.dart';
import '../models/face_embedding_model.dart';

/// Runs the supplied MobileFaceNet model and compares 192-d embeddings.
///
/// The model must be bundled at [modelAsset]. This service intentionally has
/// no fallback vector: a missing model must leave attendance locked.
class FaceEmbeddingService {
  static const modelAsset = FaceEmbeddingModel.assetPath;
  Interpreter? _interpreter;

  Future<List<double>> createEmbedding(LivenessResult liveness) async {
    try {
      _interpreter ??= await Interpreter.fromAsset(modelAsset);
    } catch (_) {
      throw StateError(
        'MobileFaceNet model missing. Add $modelAsset and declare it in pubspec.yaml.',
      );
    }
    _validateModelTensors(_interpreter!);

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
      width: FaceEmbeddingModel.inputWidth,
      height: FaceEmbeddingModel.inputHeight,
    );
    final input = [
      List.generate(
        FaceEmbeddingModel.inputHeight,
        (y) => List.generate(FaceEmbeddingModel.inputWidth, (x) {
          final pixel = face.getPixel(x, y);
          return [
            // This model expects RGB values normalized to approximately [-1, 1].
            (pixel.r - 127.5) / 128.0,
            (pixel.g - 127.5) / 128.0,
            (pixel.b - 127.5) / 128.0,
          ];
        }),
      ),
    ];
    final output = [
      List<double>.filled(FaceEmbeddingModel.embeddingDimensions, 0),
    ];
    _interpreter!.run(input, output);
    final embedding = output.first;
    if (embedding.any((value) => !value.isFinite)) {
      throw StateError('The model returned a non-finite embedding.');
    }
    return embedding;
  }

  /// Euclidean distance used by the source app. A lower value is closer.
  static double euclideanDistance(List<double> a, List<double> b) {
    if (a.length != FaceEmbeddingModel.embeddingDimensions ||
        b.length != FaceEmbeddingModel.embeddingDimensions) {
      throw ArgumentError(
        'Both face embeddings must contain '
        '${FaceEmbeddingModel.embeddingDimensions} values.',
      );
    }
    var squaredDistance = 0.0;
    for (var i = 0; i < a.length; i++) {
      final difference = a[i] - b[i];
      squaredDistance += difference * difference;
    }
    return math.sqrt(squaredDistance);
  }

  static void _validateModelTensors(Interpreter interpreter) {
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    const expectedInput = [1, 112, 112, 3];
    const expectedOutput = [1, FaceEmbeddingModel.embeddingDimensions];
    if (inputShape.toString() != expectedInput.toString()) {
      throw StateError(
        'Unsupported MobileFaceNet input shape $inputShape; '
        'expected $expectedInput.',
      );
    }
    if (outputShape.toString() != expectedOutput.toString()) {
      throw StateError(
        'Unsupported MobileFaceNet output shape $outputShape; '
        'expected $expectedOutput.',
      );
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
