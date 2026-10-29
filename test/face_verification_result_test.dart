import 'package:flutter_test/flutter_test.dart';
import 'package:attendance/features/module_3_qr_scan/models/face_verification_result.dart';

void main() {
  group('Module 3: Face verification gate', () {
    const now = 1700000000000;

    FaceVerificationResult result({
      bool livenessPassed = true,
      bool identityMatched = true,
      double cosineDistance = 0.20,
      int? verifiedAtMs,
    }) {
      return FaceVerificationResult(
        livenessPassed: livenessPassed,
        identityMatched: identityMatched,
        cosineDistance: cosineDistance,
        studentId: 'STU_001',
        verifiedAtMs: verifiedAtMs ?? now,
      );
    }

    test('Passed liveness + match under 0.40 unlocks the scanner', () {
      expect(result().isVerified, isTrue);
      expect(result().isUsableAt(now), isTrue);
    });

    test('Cosine distance exactly 0.40 does not count as a match', () {
      expect(result(cosineDistance: 0.40).isVerified, isFalse);
      expect(result(cosineDistance: 0.39).isVerified, isTrue);
    });

    test('Liveness or identity failure keeps the scanner locked', () {
      expect(result(livenessPassed: false).isVerified, isFalse);
      expect(result(identityMatched: false).isVerified, isFalse);
    });

    test('Stale verification result cannot unlock the scanner', () {
      final old = result(
        verifiedAtMs: now - FaceVerificationResult.maxAgeMs - 1,
      );
      expect(old.isVerified, isTrue);
      expect(old.isUsableAt(now), isFalse);
    });

    test('Verification issued in the future is rejected', () {
      final future = result(verifiedAtMs: now + 1000);
      expect(future.isUsableAt(now), isFalse);
    });

    test('Debug bypass produces a usable result', () {
      final bypass = FaceVerificationResult.debugBypass(nowMs: now);
      expect(bypass.isUsableAt(now), isTrue);
    });
  });
}
