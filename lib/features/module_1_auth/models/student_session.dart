import '../../module_5_embedding/models/enrollment_profile.dart';

/// Authenticated student or administrator context for the app.
class StudentSession {
  final String studentId;
  final String displayName;
  final String role;
  final String deviceId;
  String sessionToken;
  String serverUrl;
  final bool offline;
  final bool isAdmin;
  final bool hasStudentIdentity;
  EnrollmentProfile? enrollment;

  StudentSession({
    required this.studentId,
    this.displayName = '',
    required this.deviceId,
    required this.sessionToken,
    this.serverUrl = '',
    this.role = 'student',
    this.offline = true,
    this.isAdmin = false,
    this.hasStudentIdentity = true,
    this.enrollment,
  });

  bool get isEnrolled => enrollment != null;

  factory StudentSession.offline({
    required String studentId,
    required String deviceId,
  }) {
    final issuedAt = DateTime.now().millisecondsSinceEpoch;
    final cleanStudentId = studentId.trim();
    return StudentSession(
      studentId: cleanStudentId,
      displayName: cleanStudentId,
      deviceId: deviceId,
      sessionToken: 'offline.$cleanStudentId.$issuedAt',
    );
  }

  factory StudentSession.online({
    required String studentId,
    required String displayName,
    required String deviceId,
    required String accessToken,
    required bool isAdmin,
    bool hasStudentIdentity = true,
    EnrollmentProfile? enrollment,
    String serverUrl = '',
  }) => StudentSession(
    studentId: studentId,
    displayName: displayName,
    deviceId: deviceId,
    sessionToken: accessToken,
    serverUrl: serverUrl,
    role: isAdmin ? 'admin' : 'student',
    isAdmin: isAdmin,
    hasStudentIdentity: hasStudentIdentity,
    offline: false,
    enrollment: enrollment,
  );
}
