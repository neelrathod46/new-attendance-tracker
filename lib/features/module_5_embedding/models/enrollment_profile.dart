import 'face_embedding_model.dart';

/// The enrolled reference vector is supplied by Module 1 after authenticated
/// enrollment. It is deliberately not persisted in this prototype.
class EnrollmentProfile {
  static const embeddingDimensions = FaceEmbeddingModel.embeddingDimensions;

  final String studentId;
  final List<double> embedding;

  EnrollmentProfile({required this.studentId, required List<double> embedding})
    : embedding = List.unmodifiable(embedding) {
    if (this.embedding.length != embeddingDimensions) {
      throw ArgumentError.value(
        this.embedding.length,
        'embedding.length',
        'This MobileFaceNet model returns $embeddingDimensions values.',
      );
    }
  }
}
