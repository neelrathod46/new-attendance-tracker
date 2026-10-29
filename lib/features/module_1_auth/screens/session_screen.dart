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
            'Request sent. Your saved identity stays unchanged until the lecturer approves it.',
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
        title: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: Color(0xFF38BDF8)),
            SizedBox(width: 10),
            Text('Campus Check-in'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _signOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                const Text(
                  'YOUR ACCOUNT',
                  style: TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Hello, ${session.displayName.split(' ').first}',
                  style: const TextStyle(
                    fontSize: 27,
                    letterSpacing: -0.6,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your identity and face enrollment are managed for this college.',
                  style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(19),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: const Color(0xFF12334A),
                              child: Text(
                                session.displayName.trim().isEmpty
                                    ? '?'
                                    : session.displayName
                                          .trim()[0]
                                          .toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF7DD3FC),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    session.studentId,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              enrolled
                                  ? Icons.verified_rounded
                                  : Icons.info_outline_rounded,
                              color: enrolled
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFFBBF24),
                            ),
                          ],
                        ),
                        const SizedBox(height: 17),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(
                              session.offline
                                  ? Icons.phone_android
                                  : Icons.wifi_rounded,
                              color: const Color(0xFF38BDF8),
                              size: 17,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                session.offline
                                    ? 'Offline demo profile'
                                    : 'Connected to lecturer laptop',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              enrolled ? 'FACE READY' : 'FACE NEEDED',
                              style: TextStyle(
                                color: enrolled
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFFBBF24),
                                fontSize: 9,
                                letterSpacing: .7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'ATTENDANCE',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: enrolled
                      ? () => _openLiveness(LivenessMode.verify)
                      : null,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Verify and check in'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  enrolled
                      ? 'Complete the live face check, then scan the current projector code.'
                      : 'Enroll your face first. The scanner unlocks only after a successful face match.',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => _openLiveness(LivenessMode.enroll),
                  icon: Icon(
                    enrolled
                        ? Icons.manage_accounts_outlined
                        : Icons.face_retouching_natural,
                  ),
                  label: Text(
                    enrolled
                        ? session.offline
                              ? 'Reset demo face enrollment'
                              : 'Request face replacement'
                        : 'Enroll my face',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFFBAE6FD),
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                ),
                if (!session.offline && session.hasStudentIdentity) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _requestProfileChange,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Request a name or roll correction'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: const Color(0xFFBAE6FD),
                      side: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: Color(0xFF38BDF8),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your college name, roll number, and registered face are locked. Changes take effect only after lecturer approval.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (session.offline) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _explainOfflineDemo,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('About the local demo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
