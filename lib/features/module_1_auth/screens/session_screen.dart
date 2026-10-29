import 'package:flutter/material.dart';

import '../../module_4_liveness/models/liveness_mode.dart';
import '../../module_4_liveness/screens/liveness_screen.dart';
import '../models/student_session.dart';
import 'auth_screen.dart';

/// Post-login card: uid, role, device, offline token, enroll / check-in.
class SessionScreen extends StatefulWidget {
  final StudentSession session;

  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  StudentSession get session => widget.session;

  Future<void> _openLiveness(LivenessMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivenessScreen(session: session, mode: mode),
      ),
    );
    if (mounted) setState(() {});
  }

  void _skipRosterSync() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Roster sync skipped. Check-in stays on this device.'),
      ),
    );
    print('[AUTH] Online roster sync bypassed.');
  }

  @override
  Widget build(BuildContext context) {
    final enrolled = session.isEnrolled;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Module 1: Session'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.badge_outlined, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    const Text(
                      'Interactive session card',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        session.role.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _row('uid', session.studentId),
                _row('device (demo)', session.deviceId),
                _row('offline token (mock)', session.sessionToken),
                _row(
                  'face',
                  enrolled ? 'Enrolled on this phone' : 'Not enrolled',
                ),
                _row('mode', session.offline ? 'OFFLINE' : 'ONLINE'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _skipRosterSync,
            icon: const Icon(Icons.cloud_off),
            label: const Text('Skip live roster sync'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _openLiveness(LivenessMode.enroll),
            icon: const Icon(Icons.face_retouching_natural),
            label: Text(enrolled ? 'Re-enroll face' : 'Enroll face'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: enrolled
                ? () => _openLiveness(LivenessMode.verify)
                : null,
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Check in (liveness → QR)'),
          ),
          if (!enrolled)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Enroll a face on this device before the QR scanner can unlock.',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }
}
