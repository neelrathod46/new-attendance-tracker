import 'package:flutter/material.dart';

import '../../module_5_embedding/models/enrollment_profile.dart';
import '../models/auth_validators.dart';
import '../models/student_session.dart';
import '../services/device_binding.dart';
import '../services/local_attendance_api.dart';
import '../services/student_profile_store.dart';
import 'lecturer_qr_screen.dart';
import 'session_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _roll = TextEditingController();
  bool _busy = false;
  String? _notice;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _restoreProfile();
  }

  Future<void> _restoreProfile() async {
    try {
      final session = await StudentProfileStore.load();
      if (session == null || !mounted) return;
      LocalAttendanceApi.configureServer(session.serverUrl);
      // Session tokens live in server memory. Refresh after a server restart.
      try {
        final refreshed = await LocalAttendanceApi.claimStudent(
          rollNo: session.studentId,
          fullName: session.displayName,
        );
        session.sessionToken = refreshed['token'] as String;
        final vector = refreshed['embedding'];
        if (vector is List) {
          session.enrollment = EnrollmentProfile(
            studentId: session.studentId,
            embedding: vector.map((v) => (v as num).toDouble()).toList(),
          );
        }
        await StudentProfileStore.save(session);
      } catch (error) {
        print('[AUTH] Saved profile restored; server refresh deferred: $error');
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
      );
    } catch (error) {
      print('[AUTH] Could not restore saved profile: $error');
    }
  }

  Future<void> _register() async {
    final roll = _roll.text.trim().toUpperCase();
    final name = _name.text.trim();
    final validation = AuthValidators.studentId(roll);
    if (validation != null) return _show(validation, error: true);
    if (name.length < 2) {
      return _show(
        'Enter your full name as it appears in the college roster.',
        error: true,
      );
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final serverUrl = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const LecturerQrScreen()),
      );
      if (serverUrl == null || !mounted) return;
      LocalAttendanceApi.configureServer(serverUrl);
      final result = await LocalAttendanceApi.claimStudent(
        rollNo: roll,
        fullName: name,
      );
      final raw = result['embedding'];
      final embedding = raw is List
          ? raw.map((v) => (v as num).toDouble()).toList()
          : null;
      final session = StudentSession.online(
        studentId: result['rollNo'] as String,
        displayName: result['fullName'] as String,
        deviceId: await readDeviceId(),
        accessToken: result['token'] as String,
        serverUrl: serverUrl,
        isAdmin: false,
        enrollment: embedding == null
            ? null
            : EnrollmentProfile(
                studentId: result['rollNo'] as String,
                embedding: embedding,
              ),
      );
      await StudentProfileStore.save(session);
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
    final validation = AuthValidators.studentId(_roll.text);
    if (validation != null) return _show(validation, error: true);
    final session = StudentSession.offline(
      studentId: _roll.text,
      deviceId: await readDeviceId(),
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Campus Check-in')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 22),
                const Icon(
                  Icons.school_rounded,
                  size: 58,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Student attendance',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Register once with your college roster. Returning students can use the saved profile and verify their face before class.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), height: 1.5),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'First-time registration',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Enter your roster details, then scan the lecturer QR to connect.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _name,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_outline),
                            labelText: 'Full name from college roster',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _roll,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.badge_outlined),
                            labelText: 'College roll number',
                            hintText: '25BCS001',
                          ),
                        ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _notice!,
                              style: TextStyle(
                                color: _error
                                    ? const Color(0xFFFDA4AF)
                                    : const Color(0xFF7DD3FC),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _register,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.qr_code_scanner),
                          label: Text(
                            _busy
                                ? 'Connecting…'
                                : 'Scan lecturer QR and register',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _offlineDemo,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Try local camera demo'),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Demo mode uses the camera flow without saving attendance.',
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
