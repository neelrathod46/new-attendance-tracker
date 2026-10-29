import 'package:flutter/material.dart';

import '../../module_5_embedding/models/enrollment_profile.dart';
import '../models/auth_validators.dart';
import '../models/student_session.dart';
import '../services/device_binding.dart';
import '../services/local_attendance_api.dart';
import 'session_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _roll = TextEditingController();
  final _serverUrl = TextEditingController(text: LocalAttendanceApi.baseUrl);
  bool _registering = true;
  bool _busy = false;
  String? _notice;
  bool _error = false;

  @override
  void dispose() {
    _name.dispose();
    _roll.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final roll = _roll.text.trim().toUpperCase();
    final name = _name.text.trim();
    final rollError = AuthValidators.studentId(roll);
    if (rollError != null) return _show(rollError, error: true);
    if (name.length < 2) {
      return _show(
        'Enter your name exactly as it appears in the college roster.',
        error: true,
      );
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      LocalAttendanceApi.configureServer(_serverUrl.text);
      print(
        '[AUTH] Connecting to lecturer LAN server: ${LocalAttendanceApi.baseUrl}',
      );
      final result = await LocalAttendanceApi.claimStudent(
        rollNo: roll,
        fullName: name,
      );
      final embeddingRaw = result['embedding'];
      final embedding = embeddingRaw is List
          ? embeddingRaw.map((value) => (value as num).toDouble()).toList()
          : null;
      final session = StudentSession.online(
        studentId: result['rollNo'] as String,
        displayName: result['fullName'] as String,
        deviceId: await readDeviceId(),
        accessToken: result['token'] as String,
        isAdmin: false,
        enrollment: embedding == null
            ? null
            : EnrollmentProfile(
                studentId: result['rollNo'] as String,
                embedding: embedding,
              ),
      );
      print('[AUTH] LAN session ready for ${session.studentId}.');
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
      );
    } catch (error) {
      _show(error.toString().replaceFirst('HttpException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message, {required bool error}) {
    if (mounted) {
      setState(() {
        _notice = message;
        _error = error;
      });
    }
  }

  Future<void> _offlineDemo() async {
    final error = AuthValidators.studentId(_roll.text);
    if (error != null) return _show(error, error: true);
    setState(() => _busy = true);
    try {
      final session = StudentSession.offline(
        studentId: _roll.text,
        deviceId: await readDeviceId(),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.qr_code_2_rounded, color: Color(0xFF38BDF8)),
          SizedBox(width: 10),
          Text('Campus Check-in'),
        ],
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF12334A), Color(0xFF17243A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFF28425A)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STUDENT ATTENDANCE',
                        style: TextStyle(
                          color: Color(0xFF7DD3FC),
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 9),
                      Text(
                        'Ready for class?',
                        style: TextStyle(
                          fontSize: 25,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Connect to your lecturer, verify your identity, then scan the live class code.',
                        style: TextStyle(
                          color: Color(0xFFB8C7D9),
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Connect to your class',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Use the same institute Wi-Fi as your lecturer.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _serverUrl,
                          enabled: !_busy,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.wifi_rounded),
                            labelText: 'Lecturer server address',
                            hintText: 'http://192.168.1.20:8765',
                            helperText:
                                'Use the Wi-Fi URL shown in the lecturer terminal. Do not use localhost or 10.0.2.2.',
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('First time'),
                              icon: Icon(Icons.person_add_alt_1),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Returning'),
                              icon: Icon(Icons.login_rounded),
                            ),
                          ],
                          selected: {_registering},
                          onSelectionChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  _registering = value.single;
                                  _notice = null;
                                }),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _name,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            labelText: 'Full name from college roster',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _roll,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _busy ? null : _connect(),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.badge_outlined),
                            labelText: 'College roll number',
                            hintText: '25BCS001',
                          ),
                        ),
                        if (_notice != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  (_error
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF38BDF8))
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _error
                                      ? Icons.error_outline_rounded
                                      : Icons.info_outline_rounded,
                                  size: 18,
                                  color: _error
                                      ? const Color(0xFFFB7185)
                                      : const Color(0xFF38BDF8),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _notice!,
                                    style: TextStyle(
                                      color: _error
                                          ? const Color(0xFFFDA4AF)
                                          : const Color(0xFF7DD3FC),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _busy
                                ? 'Connecting…'
                                : _registering
                                ? 'Register with college roster'
                                : 'Continue to your account',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _offlineDemo,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Try local camera demo'),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Demo mode exercises the face and QR flow without saving attendance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF718096), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
