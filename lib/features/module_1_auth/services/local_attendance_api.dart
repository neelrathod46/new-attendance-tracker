import 'dart:convert';
import 'dart:io';

/// HTTP client for the lecturer laptop's local classroom server.
class LocalAttendanceApi {
  static const defaultServerUrl = String.fromEnvironment(
    'ATTENDANCE_SERVER_URL',
    defaultValue: 'http://10.0.2.2:8765',
  );
  static String _serverUrl = defaultServerUrl;

  static String get baseUrl => _serverUrl;

  static void configureServer(String value) {
    final cleaned = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
        'Enter the lecturer server address like http://192.168.1.20:8765.',
      );
    }
    _serverUrl = cleaned;
  }

  static Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map ? decoded['error'] : null;
        throw HttpException(
          message?.toString() ?? 'Server returned ${response.statusCode}.',
        );
      }
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException(
        'Unexpected response from the attendance server.',
      );
    } on SocketException {
      throw const HttpException(
        'Could not reach the lecturer laptop. Check Wi-Fi and the server address.',
      );
    } on HttpException {
      rethrow;
    } on FormatException {
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> claimStudent({
    required String rollNo,
    required String fullName,
  }) => _request(
    '/api/student/claim',
    method: 'POST',
    body: {'rollNo': rollNo, 'fullName': fullName},
  );

  static Future<void> saveInitialEnrollment(
    String token,
    List<double> embedding,
  ) async {
    await _request(
      '/api/student/enrollment',
      method: 'POST',
      token: token,
      body: {'embedding': embedding},
    );
  }

  static Future<void> requestIdentityChange(
    String token, {
    String? rollNo,
    String? fullName,
    String? reason,
    List<double>? embedding,
  }) async {
    await _request(
      '/api/student/identity-request',
      method: 'POST',
      token: token,
      body: {
        'rollNo': rollNo,
        'fullName': fullName,
        'reason': reason,
        'embedding': ?embedding,
      },
    );
  }

  static Future<Map<String, dynamic>> submitCheckIn({
    required String token,
    required String sessionId,
    required String courseCode,
    required int nonce,
    required int timestamp,
    required List<double> embedding,
  }) => _request(
    '/api/attendance/check-in',
    method: 'POST',
    token: token,
    body: {
      'qr': {
        'sessionId': sessionId,
        'session': courseCode,
        'nonce': nonce,
        'ts': timestamp,
      },
      'embedding': embedding,
    },
  );
}
