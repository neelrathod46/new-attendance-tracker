import 'dart:convert';

/// Status of the QR token validation adhering to anti-proxy rules
enum TokenValidationStatus {
  valid,
  expired,
  replayAttack,
  staleToken,
  invalidFormat,
  clockDesync,
}

/// Dynamic time-bound QR payload model
/// Expected schema: {"session": "CS101", "nonce": 849120, "ts": 1793212800142}
class QrPayload {
  final String session;
  final String sessionId;
  final int nonce;
  final int timestamp;
  final String rawJson;
  final int scannedAt;
  final int ageMs;
  final TokenValidationStatus status;
  final String statusMessage;

  const QrPayload({
    required this.session,
    this.sessionId = '',
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
    int? latestAcceptedTs,
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

      if (session == null ||
          session.isEmpty ||
          nonceVal == null ||
          tsVal == null) {
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

      if (nonce <= 0 || ts <= 0) {
        return QrPayload(
          session: session,
          sessionId: decoded['sessionId']?.toString() ?? '',
          nonce: nonce,
          timestamp: ts,
          rawJson: raw,
          scannedAt: now,
          ageMs: -1,
          status: TokenValidationStatus.invalidFormat,
          statusMessage: 'Invalid Token | nonce and ts must be positive',
        );
      }

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
          statusMessage: 'Code already used | Scan the current class code',
        );
      }

      // Only the newest code for the session may be accepted. The projector
      // emits random nonces, so the generation timestamp is the client-side
      // ordering signal: any code at or below the last accepted ts is stale.
      if (latestAcceptedTs != null && ts <= latestAcceptedTs) {
        return QrPayload(
          session: session,
          nonce: nonce,
          timestamp: ts,
          rawJson: raw,
          scannedAt: now,
          ageMs: ageMs,
          status: TokenValidationStatus.staleToken,
          statusMessage: 'Code replaced | Scan the latest class code',
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
              'Phone time differs | Check your device clock and scan again',
        );
      }

      // Match the server's 3-second QR lifetime.
      if (ageMs > 3000) {
        final ageSec = (ageMs / 1000.0).toStringAsFixed(1);
        return QrPayload(
          session: session,
          nonce: nonce,
          timestamp: ts,
          rawJson: raw,
          scannedAt: now,
          ageMs: ageMs,
          status: TokenValidationStatus.expired,
          statusMessage: 'Code expired | Generated ${ageSec}s ago; scan again',
        );
      }

      // Valid token (0 <= ageMs <= 3000)
      final ageDisplay = ageMs >= 1000
          ? '${(ageMs / 1000.0).toStringAsFixed(1)}s'
          : '${ageMs < 0 ? 0 : ageMs}ms';
      return QrPayload(
        session: session,
        sessionId: decoded['sessionId']?.toString() ?? '',
        nonce: nonce,
        timestamp: ts,
        rawJson: raw,
        scannedAt: now,
        ageMs: ageMs < 0 ? 0 : ageMs,
        status: TokenValidationStatus.valid,
        statusMessage: 'Code ready | Generated $ageDisplay ago',
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
