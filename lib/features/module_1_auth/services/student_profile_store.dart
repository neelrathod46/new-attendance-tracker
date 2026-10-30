import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/student_session.dart';
import '../../module_5_embedding/models/enrollment_profile.dart';

/// Stores a student's local profile encrypted with an Android Keystore key.
class StudentProfileStore {
  static const _channel = MethodChannel('attendance/student_profile');

  static Future<void> save(StudentSession session) async {
    if (session.offline || session.serverUrl.isEmpty) return;
    await _channel.invokeMethod<void>('save', {
      'profile': jsonEncode({
        'studentId': session.studentId,
        'displayName': session.displayName,
        'serverUrl': session.serverUrl,
        'sessionToken': session.sessionToken,
        'embedding': session.enrollment?.embedding,
      }),
    });
  }

  static Future<StudentSession?> load() async {
    final raw = await _channel.invokeMethod<String>('load');
    if (raw == null || raw.isEmpty) return null;
    final profile = jsonDecode(raw) as Map<String, dynamic>;
    final roll = profile['studentId'] as String;
    final embeddingRaw = profile['embedding'];
    final embedding = embeddingRaw is List
        ? embeddingRaw.map((value) => (value as num).toDouble()).toList()
        : null;
    return StudentSession.online(
      studentId: roll,
      displayName: profile['displayName'] as String,
      deviceId: 'local-profile',
      accessToken: profile['sessionToken'] as String? ?? '',
      serverUrl: profile['serverUrl'] as String? ?? '',
      isAdmin: false,
      enrollment: embedding == null
          ? null
          : EnrollmentProfile(studentId: roll, embedding: embedding),
    );
  }

  static Future<void> clear() => _channel.invokeMethod<void>('clear');
}
