import 'package:attendance/features/module_1_auth/models/auth_validators.dart';
import 'package:attendance/features/module_1_auth/models/student_session.dart';
import 'package:attendance/features/module_5_embedding/models/enrollment_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Module 1: offline auth', () {
    test('student id requires a trimmed value of at least 3 characters', () {
      expect(AuthValidators.studentId(''), 'Enter a student ID');
      expect(
        AuthValidators.studentId('  ab  '),
        'Student ID must be at least 3 characters',
      );
      expect(AuthValidators.studentId('STU_001'), isNull);
    });

    test('password is optional when continuing offline', () {
      expect(AuthValidators.password('', requiredForSubmit: false), isNull);
      expect(
        AuthValidators.password('123', requiredForSubmit: true),
        'Password must be at least 6 characters',
      );
    });

    test('offline session starts without an enrollment vector', () {
      final session = StudentSession.offline(
        studentId: ' STU_001 ',
        deviceId: 'device-1',
      );
      expect(session.studentId, 'STU_001');
      expect(session.offline, isTrue);
      expect(session.isEnrolled, isFalse);
      expect(session.sessionToken, contains('offline.STU_001'));
    });

    test('enrollment profile rejects non-128 vectors', () {
      expect(
        () => EnrollmentProfile(studentId: 'STU_001', embedding: const [1, 2]),
        throwsArgumentError,
      );
    });
  });
}
