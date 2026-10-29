import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../module_5_embedding/models/enrollment_profile.dart';
import '../models/auth_validators.dart';
import '../models/student_session.dart';
import '../services/device_binding.dart';
import '../services/supabase_client.dart';
import 'session_screen.dart';

/// Online registration can only claim an admin-loaded roster entry whose
/// name, roll number, and college email match this authenticated account.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  var _registering = false;
  var _busy = false;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _emailController,
      _passwordController,
      _nameController,
      _rollController,
    ]) {
      controller.addListener(() {
        if (mounted) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  Future<void> _restoreSession() async {
    final user = AppSupabase.client.auth.currentUser;
    if (user == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _openOnlineSession(user);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = _friendlyError(error);
        _noticeIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  Future<void> _submitOnline() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      _showNotice('Enter your college email address.', error: true);
      return;
    }
    final passwordError = AuthValidators.password(
      password,
      requiredForSubmit: true,
    );
    if (passwordError != null) {
      _showNotice(passwordError, error: true);
      return;
    }
    if (_registering) {
      if (_nameController.text.trim().length < 2) {
        _showNotice('Enter your name as it appears on the college roster.', error: true);
        return;
      }
      if (_rollController.text.trim().isEmpty) {
        _showNotice('Enter the roll number assigned by your college.', error: true);
        return;
      }
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final client = AppSupabase.client;
      if (_registering) {
        print('[AUTH] Creating Supabase account for $email.');
        final response = await client.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': _nameController.text.trim(),
            'roll_no': _rollController.text.trim().toUpperCase(),
          },
        );
        if (response.session == null) {
          _showNotice(
            'Account created. Confirm your college email, then sign in here to claim your roster entry.',
          );
          return;
        }
        await _openOnlineSession(response.user!);
      } else {
        print('[AUTH] Signing in to Supabase for $email.');
        final response = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        await _openOnlineSession(response.user!);
      }
    } catch (error) {
      print('[AUTH] Supabase sign-in/registration failed: $error');
      _showNotice(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOnlineSession(User user) async {
    final client = AppSupabase.client;
    final isAdmin = (await client.rpc('is_college_admin')) as bool;
    var profile = await client
        .from('student_profiles')
        .select('roster_id, student_roster(roll_no, full_name)')
        .eq('user_id', user.id)
        .maybeSingle();

    if (profile == null && isAdmin) {
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final session = StudentSession.online(
        studentId: 'ADMIN',
        displayName: (metadata['full_name'] ?? user.email ?? 'College administrator').toString(),
        deviceId: await readDeviceId(),
        accessToken: client.auth.currentSession?.accessToken ?? '',
        isAdmin: true,
        hasStudentIdentity: false,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
      );
      return;
    }

    if (profile == null) {
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final roll = (metadata['roll_no'] ?? _rollController.text).toString();
      final name = (metadata['full_name'] ?? _nameController.text).toString();
      if (roll.trim().isEmpty || name.trim().isEmpty) {
        throw StateError(
          'Your account is not linked to a student roster entry yet. Sign out and use Create student account with your name and roll number.',
        );
      }
      print('[AUTH] Claiming roster entry for ${roll.toUpperCase()}.');
      await client.rpc(
        'claim_student_identity',
        params: {'p_roll_no': roll, 'p_full_name': name},
      );
      profile = await client
          .from('student_profiles')
          .select('roster_id, student_roster(roll_no, full_name)')
          .eq('user_id', user.id)
          .single();
    }

    final roster = Map<String, dynamic>.from(profile['student_roster'] as Map);
    final enrollmentRow = await client
        .from('face_enrollments')
        .select('embedding')
        .eq('user_id', user.id)
        .maybeSingle();
    final embedding = enrollmentRow == null
        ? null
        : _parseEmbedding(enrollmentRow['embedding']);
    final deviceId = await readDeviceId();
    final session = StudentSession.online(
      studentId: roster['roll_no'] as String,
      displayName: roster['full_name'] as String,
      deviceId: deviceId,
      accessToken: client.auth.currentSession?.accessToken ?? '',
      isAdmin: isAdmin,
      enrollment: embedding == null
          ? null
          : EnrollmentProfile(
              studentId: roster['roll_no'] as String,
              embedding: embedding,
            ),
    );
    print('[AUTH] Online session ready for ${session.studentId}.');
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
    );
  }

  List<double> _parseEmbedding(dynamic raw) {
    if (raw is List) return raw.map((value) => (value as num).toDouble()).toList();
    final text = raw.toString().trim();
    final content = text.startsWith('[') && text.endsWith(']')
        ? text.substring(1, text.length - 1)
        : text;
    return content
        .split(',')
        .map((value) => double.parse(value.trim()))
        .toList(growable: false);
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.contains('Invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    if (message.contains('User already registered')) {
      return 'An account already exists for this email. Sign in instead.';
    }
    if (message.contains('Failed host lookup') || message.contains('SocketException')) {
      return 'Could not reach Supabase. Check your connection and try again.';
    }
    return message;
  }

  void _showNotice(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = error;
    });
  }

  Future<void> _continueOffline() async {
    final error = AuthValidators.studentId(_rollController.text);
    if (error != null) {
      _showNotice(error, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final session = StudentSession.offline(
        studentId: _rollController.text,
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
  Widget build(BuildContext context) {
    final borderColor = const Color(0xFF334155);
    return Scaffold(
      appBar: AppBar(title: const Text('Student Attendance')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Register with your college identity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your name and roll number must match the college roster. After registration, only an administrator can approve identity changes.',
            style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 22),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sign in')),
              ButtonSegment(value: true, label: Text('Create account')),
            ],
            selected: {_registering},
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() {
                    _registering = selection.single;
                    _notice = null;
                  }),
          ),
          const SizedBox(height: 20),
          if (_registering) ...[
            TextField(
              controller: _nameController,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Full name as listed by your college',
                border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _rollController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: _registering ? 'Roll number' : 'Roll number (offline demo)',
              hintText: '25BCS001',
              border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _emailController,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'College email',
              border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 16),
            Text(
              _notice!,
              style: TextStyle(
                color: _noticeIsError ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
              ),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : _submitOnline,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_registering ? Icons.person_add_alt_1 : Icons.login),
            label: Text(_registering ? 'Create college account' : 'Sign in'),
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Offline demo',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Exercises the camera and face flow locally. It does not claim the college roster entry or save attendance online.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _continueOffline,
            icon: const Icon(Icons.cloud_off),
            label: const Text('Continue offline demo'),
          ),
        ],
      ),
    );
  }
}
