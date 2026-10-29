import 'package:flutter_test/flutter_test.dart';
import 'package:attendance/features/module_3_qr_scan/models/qr_payload.dart';

void main() {
  group('Module 3: QR Token Validation Rules', () {
    test('Valid token within 2.0s hard expiry', () {
      final now = 1700000000000;
      final payloadJson = '{"session":"CS101","nonce":123456,"ts":${now - 400}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {},
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isTrue);
      expect(payload.status, TokenValidationStatus.valid);
      expect(payload.ageMs, 400);
      expect(payload.session, 'CS101');
      expect(payload.nonce, 123456);
      expect(payload.statusMessage, contains('Valid Token | Generated 400ms ago'));
    });

    test('Expired token (> 2000ms) is rejected', () {
      final now = 1700000000000;
      final payloadJson = '{"session":"CS101","nonce":123457,"ts":${now - 3200}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {},
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.expired);
      expect(payload.ageMs, 3200);
      expect(
        payload.statusMessage,
        contains('Expired Token | Generated 3.2s ago (Rejected)'),
      );
    });

    test('Replay attack (duplicate nonce) is rejected', () {
      final now = 1700000000000;
      final payloadJson = '{"session":"CS101","nonce":999999,"ts":${now - 200}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {999999}, // Already used
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.replayAttack);
      expect(payload.statusMessage, contains('Replay Attack Detected'));
    });

    test('Malformed payload is rejected', () {
      final payload = QrPayload.parse(
        'not a json payload',
        usedNonces: {},
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.invalidFormat);
    });
  });
}
