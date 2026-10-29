/// Live form rules for Module 1. Online sign-in will reuse the same checks.
class AuthValidators {
  static String? studentId(String raw) {
    final id = raw.trim();
    if (id.isEmpty) return 'Enter a student ID';
    if (id.length < 3) return 'Student ID must be at least 3 characters';
    return null;
  }

  static String? password(String raw, {required bool requiredForSubmit}) {
    if (!requiredForSubmit) return null;
    if (raw.isEmpty) return 'Enter a password';
    if (raw.length < 6) return 'Password must be at least 6 characters';
    return null;
  }
}
