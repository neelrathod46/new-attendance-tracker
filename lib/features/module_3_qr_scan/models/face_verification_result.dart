/// Proof that face liveness and identity verification both passed.
///
/// Module 3 only consumes this result. Modules 4 (liveness) and 5 (embedding
/// match) produce it; there is no face-verification bypass.
class FaceVerificationResult {
  /// Cosine distance at or below which two 128-d embeddings count as a match.
  static const double matchThreshold = 0.40;

  /// How long a verification result stays usable before the student must redo it.
  static const int maxAgeMs = 5 * 60 * 1000;

  final bool livenessPassed;
  final bool identityMatched;
  final double cosineDistance;
  final String studentId;
  final int verifiedAtMs;

  const FaceVerificationResult({
    required this.livenessPassed,
    required this.identityMatched,
    required this.cosineDistance,
    required this.studentId,
    required this.verifiedAtMs,
  });

  bool get isVerified =>
      livenessPassed && identityMatched && cosineDistance < matchThreshold;

  /// A verification is only usable while it is fresh. A negative age means the
  /// result was issued in the future, which is treated as invalid.
  bool isUsableAt(int nowMs) {
    final ageMs = nowMs - verifiedAtMs;
    return isVerified && ageMs >= 0 && ageMs <= maxAgeMs;
  }
}
