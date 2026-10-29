import 'dart:math' as math;

import 'package:attendance/features/module_5_embedding/services/face_embedding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Module 5: embedding comparison', () {
    final basis = List<double>.filled(192, 0)..[0] = 1;

    test('identical embeddings have zero Euclidean distance', () {
      expect(
        FaceEmbeddingService.euclideanDistance(basis, basis),
        closeTo(0, 1e-12),
      );
    });

    test('orthogonal unit embeddings have Euclidean distance sqrt(2)', () {
      final orthogonal = List<double>.filled(192, 0)..[1] = 1;
      expect(
        FaceEmbeddingService.euclideanDistance(basis, orthogonal),
        closeTo(math.sqrt(2), 1e-12),
      );
    });

    test('incorrect embedding dimensions are rejected', () {
      expect(
        () => FaceEmbeddingService.euclideanDistance(const [1], const [1]),
        throwsArgumentError,
      );
    });
  });
}
