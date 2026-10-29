import 'package:attendance/features/module_5_embedding/services/face_embedding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Module 5: embedding comparison', () {
    final basis = List<double>.filled(128, 0)..[0] = 1;

    test('identical normalized embeddings have zero cosine distance', () {
      expect(
        FaceEmbeddingService.cosineDistance(basis, basis),
        closeTo(0, 1e-12),
      );
    });

    test('orthogonal embeddings fail the 0.40 identity threshold', () {
      final orthogonal = List<double>.filled(128, 0)..[1] = 1;
      expect(
        FaceEmbeddingService.cosineDistance(basis, orthogonal),
        closeTo(1, 1e-12),
      );
    });

    test('incorrect embedding dimensions are rejected', () {
      expect(
        () => FaceEmbeddingService.cosineDistance(const [1], const [1]),
        throwsArgumentError,
      );
    });
  });
}
