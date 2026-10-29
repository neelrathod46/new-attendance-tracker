import '../../module_5_embedding/models/enrollment_profile.dart';

/// In-memory student context for the offline prototype.
///
/// Supabase will later persist [enrollment] and issue a real JWT. Until then
/// the session lives only in this process and [offline] stays true.
class StudentSession {
  final String studentId;
  final String role;
  final String deviceId;
  final String sessionToken;
  final bool offline;
  EnrollmentProfile? enrollment;

  StudentSession({
    required this.studentId,
    required this.deviceId,
    required this.sessionToken,
    this.role = 'student',
    this.offline = true,
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
      deviceId: deviceId,
      sessionToken: 'offline.$cleanStudentId.$issuedAt',
    );
  }
}
