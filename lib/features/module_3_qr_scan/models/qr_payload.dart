import 'dart:convert';

/// Status of the QR token validation adhering to anti-proxy rules
enum TokenValidationStatus {
  valid,
  expired,
  replayAttack,
  invalidFormat,
  clockDesync,
}

/// Dynamic time-bound QR payload model
/// Expected schema: {"session": "CS101", "nonce": 849120, "ts": 1793212800142}
class QrPayload {
  final String session;
  final int nonce;
  final int timestamp;
  final String rawJson;
  final int scannedAt;
  final int ageMs;
  final TokenValidationStatus status;
  final String statusMessage;

  const QrPayload({
    required this.session,
    required this.nonce,
    required this.timestamp,
    required this.rawJson,
    required this.scannedAt,
    required this.ageMs,
    required this.status,
    required this.statusMessage,
  });

  bool get isValid => status == TokenValidationStatus.valid;

  /// Parses and validates the raw QR string with boundary logging support
  static QrPayload parse(
    String raw, {
    required Set<int> usedNonces,
    int? mockCurrentTimeMs,
  }) {
    final now = mockCurrentTimeMs ?? DateTime.now().millisecondsSinceEpoch;

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return QrPayload(
          session: 'UNKNOWN',
          nonce: 0,
          timestamp: 0,
          rawJson: raw,
          scannedAt: now,
          ageMs: -1,
          status: TokenValidationStatus.invalidFormat,
          statusMessage: 'Invalid QR payload: Not a JSON object',
        );
      }

      final session = decoded['session']?.toString();
      final nonceVal = decoded['nonce'];
      final tsVal = decoded['ts'];

      if (session == null || session.isEmpty || nonceVal == null || tsVal == null) {
        return QrPayload(
          session: session ?? 'UNKNOWN',
          nonce: nonceVal is int ? nonceVal : 0,
          timestamp: tsVal is int ? tsVal : 0,
          rawJson: raw,
          scannedAt: now,
          ageMs: -1,
          status: TokenValidationStatus.invalidFormat,
          statusMessage: 'Invalid Token | Missing session, nonce, or ts',
        );
      }

      final int nonce = (nonceVal is num)
          ? nonceVal.toInt()
          : int.tryParse(nonceVal.toString()) ?? 0;
      final int ts = (tsVal is num)
          ? tsVal.toInt()
          : int.tryParse(tsVal.toString()) ?? 0;
      final int ageMs = now - ts;

      // Anti-replay attack check
      if (usedNonces.contains(nonce)) {
        return QrPayload(
          session: session,
          nonce: nonce,
          timestamp: ts,
          rawJson: raw,
          scannedAt: now,
          ageMs: ageMs,
          status: TokenValidationStatus.replayAttack,
          statusMessage: 'Replay Attack Detected | Nonce $nonce already used',
        );
      }

      // Future timestamp clock skew check (> 1500ms ahead)
      if (ageMs < -1500) {
        return QrPayload(
          session: session,
          nonce: nonce,
          timestamp: ts,
          rawJson: raw,
          scannedAt: now,
          ageMs: ageMs,
          status: TokenValidationStatus.clockDesync,
          statusMessage:
              'Clock Desync | QR code timestamp is in the future (${ageMs.abs()}ms ahead)',
        );
      }

      // Hard limit of 2.0 seconds (2000 ms) as specified in rule 2.0
      if (ageMs > 2000) {
        final ageSec = (ageMs / 1000.0).toStringAsFixed(1);
        return QrPayload(
          session: session,
          nonce: nonce,
          timestamp: ts,
          rawJson: raw,
          scannedAt: now,
          ageMs: ageMs,
          status: TokenValidationStatus.expired,
          statusMessage: 'Expired Token | Generated ${ageSec}s ago (Rejected)',
        );
      }

      // Valid token (0 <= ageMs <= 2000)
      final ageDisplay = ageMs >= 1000
          ? '${(ageMs / 1000.0).toStringAsFixed(1)}s'
          : '${ageMs < 0 ? 0 : ageMs}ms';
      return QrPayload(
        session: session,
        nonce: nonce,
        timestamp: ts,
        rawJson: raw,
        scannedAt: now,
        ageMs: ageMs < 0 ? 0 : ageMs,
        status: TokenValidationStatus.valid,
        statusMessage: 'Valid Token | Generated $ageDisplay ago',
      );
    } catch (e) {
      return QrPayload(
        session: 'UNKNOWN',
        nonce: 0,
        timestamp: 0,
        rawJson: raw,
        scannedAt: now,
        ageMs: -1,
        status: TokenValidationStatus.invalidFormat,
        statusMessage: 'Malformed JSON Payload: ${e.toString()}',
      );
    }
  }
}
