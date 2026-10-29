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
    appBar: AppBar(title: const Text('Student Attendance')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Connect to your class',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use the same institute Wi-Fi as your lecturer. Your name and roll number must match the imported college roster.',
          style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
        ),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('First registration')),
            ButtonSegment(value: false, label: Text('Sign in')),
          ],
          selected: {_registering},
          onSelectionChanged: _busy
              ? null
              : (v) => setState(() {
                  _registering = v.single;
                  _notice = null;
                }),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _serverUrl,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Lecturer laptop server address',
            hintText: 'http://192.168.1.20:8765',
            helperText: 'Ask the lecturer for this address. Both devices must use the same Wi-Fi.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Full name from college roster',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _roll,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Roll number',
            hintText: '25BCS001',
            border: OutlineInputBorder(),
          ),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 14),
          Text(
            _notice!,
            style: TextStyle(
              color: _error ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_registering ? Icons.person_add_alt : Icons.login),
          label: Text(
            _registering
                ? 'Register / claim roster identity'
                : 'Sign in to local server',
          ),
        ),
        const SizedBox(height: 28),
        const Divider(),
        const Text(
          'Local camera demo',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'The demo runs face enrollment and scanning on this phone. It does not create a college attendance record.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _offlineDemo,
          icon: const Icon(Icons.phonelink_off),
          label: const Text('Continue offline demo'),
        ),
      ],
    ),
  );
}
