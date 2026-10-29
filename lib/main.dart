import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'features/module_3_qr_scan/models/face_verification_result.dart';
import 'features/module_3_qr_scan/screens/qr_scanner_screen.dart';
import 'features/module_4_liveness/screens/liveness_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Module 3 is gated on a passed liveness + identity verification. Debug builds
  // may still opt into a stand-in result to exercise the scanner directly.
  final debugBypass =
      kDebugMode && const bool.fromEnvironment('BYPASS_FACE_VERIFICATION');
  final verification = debugBypass
      ? FaceVerificationResult.debugBypass()
      : null;

  runApp(AttendanceApp(verification: verification));
}

class AttendanceApp extends StatelessWidget {
  final FaceVerificationResult? verification;

  const AttendanceApp({super.key, this.verification});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Attendance System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF22C55E),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      // Existing installs may still use the debug-only Module 3 test route.
      // Production begins with liveness; Auth will supply its enrollment profile.
      home: verification == null
          ? const LivenessScreen(enrollment: null)
          : QrScannerScreen(verification: verification),
    );
  }
}
