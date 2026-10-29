import 'package:flutter/material.dart';

import '../../module_4_liveness/models/liveness_mode.dart';
import '../../module_4_liveness/screens/liveness_screen.dart';
import '../models/student_session.dart';
import '../services/local_attendance_api.dart';
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

  void _explainOfflineDemo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Offline demo only: no roster or attendance data is sent.',
        ),
      ),
    );
    print('[AUTH] Offline demo session remains local.');
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _requestProfileChange() async {
    final roll = TextEditingController();
    final name = TextEditingController();
    final reason = TextEditingController();
    final values = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request an identity correction'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Leave fields blank if they do not need to change. The lecturer must approve this request.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: roll,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Correct roll number',
                ),
              ),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Correct full name',
                ),
              ),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for request',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length < 3 ||
                  (roll.text.trim().isEmpty && name.text.trim().isEmpty)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a requested change and a reason.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, {
                'roll': roll.text.trim(),
                'name': name.text.trim(),
                'reason': reason.text.trim(),
              });
            },
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    roll.dispose();
    name.dispose();
    reason.dispose();
    if (values == null || !mounted) return;
    try {
      await LocalAttendanceApi.requestIdentityChange(
        session.sessionToken,
        rollNo: values['roll']!.isEmpty ? null : values['roll'],
        fullName: values['name']!.isEmpty ? null : values['name'],
        reason: values['reason'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Request sent. Your saved identity stays unchanged until an admin approves it.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrolled = session.isEnrolled;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Module 1: Session'),
        actions: [
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
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
                _row('Student', session.displayName),
                _row('Roll number', session.studentId),
                _row(
                  'face',
                  enrolled
                      ? 'Enrolled · changes require lecturer approval'
                      : 'Not enrolled',
                ),
                _row(
                  'account',
                  session.offline ? 'Offline demo' : 'Lecturer laptop LAN',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!session.offline && session.hasStudentIdentity) ...[
            OutlinedButton.icon(
              onPressed: _requestProfileChange,
              icon: const Icon(Icons.edit_note),
              label: const Text('Request name or roll number correction'),
            ),
            const SizedBox(height: 10),
          ] else if (session.offline) ...[
            OutlinedButton.icon(
              onPressed: _explainOfflineDemo,
              icon: const Icon(Icons.cloud_off),
              label: const Text('About offline demo'),
            ),
          ],
          const SizedBox(height: 20),
          if (session.hasStudentIdentity)
            FilledButton.icon(
              onPressed: () => _openLiveness(LivenessMode.enroll),
              icon: const Icon(Icons.face_retouching_natural),
              label: Text(
                enrolled
                    ? session.offline
                          ? 'Re-enroll face'
                          : 'Request face replacement'
                    : 'Enroll face',
              ),
            ),
          if (session.hasStudentIdentity) const SizedBox(height: 12),
          if (session.hasStudentIdentity)
            FilledButton.icon(
              onPressed: enrolled
                  ? () => _openLiveness(LivenessMode.verify)
                  : null,
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Check in (liveness → QR)'),
            ),
          if (session.hasStudentIdentity && !enrolled)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Enroll a face on this device before the QR scanner can unlock.',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
          if (session.hasStudentIdentity && enrolled && !session.offline)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Your enrolled roll number and face cannot be edited here. Replacement requests require lecturer approval.',
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
