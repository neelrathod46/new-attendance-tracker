/// The enrolled reference vector is supplied by Module 1 after authenticated
/// enrollment. It is deliberately not persisted in this prototype.
class EnrollmentProfile {
  final String studentId;
  final List<double> embedding;

  EnrollmentProfile({required this.studentId, required List<double> embedding})
    : embedding = List.unmodifiable(embedding) {
    if (this.embedding.length != 128) {
      throw ArgumentError.value(
        this.embedding.length,
        'embedding.length',
        'MobileFaceNet enrollment embeddings must contain 128 values.',
      );
    }
  }
}
