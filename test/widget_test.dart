import 'package:flutter_test/flutter_test.dart';
import 'package:attendance/features/module_3_qr_scan/models/qr_payload.dart';

void main() {
  group('Module 3: QR Token Validation Rules', () {
    const now = 1700000000000;

    test('Valid token within the 3.0s submission window', () {
      final payloadJson =
          '{"session":"CS101","nonce":123456,"ts":${now - 400}}';

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
      expect(
        payload.statusMessage,
        contains('Valid Token | Generated 400ms ago'),
      );
    });

    test('Token just inside the 3.0s window is accepted', () {
      final payloadJson =
          '{"session":"CS101","nonce":123458,"ts":${now - 2900}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {},
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isTrue);
      expect(payload.status, TokenValidationStatus.valid);
      expect(payload.ageMs, 2900);
    });

    test('Expired token (> 3000ms) is rejected', () {
      final payloadJson =
          '{"session":"CS101","nonce":123457,"ts":${now - 3200}}';

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
      final payloadJson =
          '{"session":"CS101","nonce":999999,"ts":${now - 200}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {999999}, // Already used
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.replayAttack);
      expect(payload.statusMessage, contains('Replay Attack Detected'));
    });

    test('Superseded code (older than the last accepted ts) is rejected', () {
      final payloadJson =
          '{"session":"CS101","nonce":555555,"ts":${now - 900}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {},
        latestAcceptedTs: now - 500,
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.staleToken);
      expect(payload.statusMessage, contains('Stale Token'));
    });

    test(
      'Same generation time with a different nonce is rejected as stale',
      () {
        final payloadJson =
            '{"session":"CS101","nonce":555556,"ts":${now - 500}}';

        final payload = QrPayload.parse(
          payloadJson,
          usedNonces: {},
          latestAcceptedTs: now - 500,
          mockCurrentTimeMs: now,
        );

        expect(payload.isValid, isFalse);
        expect(payload.status, TokenValidationStatus.staleToken);
      },
    );

    test('Newer code is accepted after an older one', () {
      final payloadJson =
          '{"session":"CS101","nonce":777777,"ts":${now - 100}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {},
        latestAcceptedTs: now - 800,
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isTrue);
      expect(payload.status, TokenValidationStatus.valid);
    });

    test('Future timestamp (clock desync) is rejected', () {
      final payloadJson =
          '{"session":"CS101","nonce":888888,"ts":${now + 2000}}';

      final payload = QrPayload.parse(
        payloadJson,
        usedNonces: {},
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.clockDesync);
    });

    test('Malformed payload is rejected', () {
      final payload = QrPayload.parse('not a json payload', usedNonces: {});

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.invalidFormat);
    });

    test('Non-positive nonce is rejected', () {
      final payload = QrPayload.parse(
        '{"session":"CS101","nonce":0,"ts":${now - 100}}',
        usedNonces: {},
        mockCurrentTimeMs: now,
      );

      expect(payload.isValid, isFalse);
      expect(payload.status, TokenValidationStatus.invalidFormat);
    });
  });
}
