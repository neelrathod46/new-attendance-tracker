import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'features/module_3_qr_scan/models/face_verification_result.dart';
import 'features/module_3_qr_scan/screens/qr_scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Module 3 is gated on a passed liveness + identity verification. Modules 4/5
  // do not exist yet, so debug builds can opt into a stand-in result to exercise
  // the scanner. Release builds always start locked.
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
      home: QrScannerScreen(verification: verification),
    );
  }
}
