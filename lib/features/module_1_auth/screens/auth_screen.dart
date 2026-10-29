import 'package:flutter/material.dart';

import '../models/auth_validators.dart';
import '../models/student_session.dart';
import '../services/device_binding.dart';
import 'session_screen.dart';

/// Local login. Supabase Auth is intentionally not called; use Continue offline.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  var _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _idController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Color _borderFor(String? error, String value) {
    if (value.isEmpty) return const Color(0xFF334155);
    if (error == null) return const Color(0xFF22C55E);
    return const Color(0xFFEF4444);
  }

  Future<void> _continueOffline() async {
    final idError = AuthValidators.studentId(_idController.text);
    if (idError != null) {
      setState(() => _notice = idError);
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final deviceId = await readDeviceId();
    final session = StudentSession.offline(
      studentId: _idController.text,
      deviceId: deviceId,
    );
    print('[AUTH] Offline session student=${session.studentId}');
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SessionScreen(session: session)),
    );
  }

  void _bypassOnlineSignIn() {
    print('[AUTH] Supabase sign-in skipped; creating local session.');
    _continueOffline();
  }

  @override
  Widget build(BuildContext context) {
    final id = _idController.text;
    final password = _passwordController.text;
    final idError = AuthValidators.studentId(id);
    final passwordError = AuthValidators.password(
      password,
      requiredForSubmit: false,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Module 1: Student Login')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Offline attendance prototype',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Face enrollment, liveness, identity match, and QR scanning run on this phone. Class roster sync needs Supabase later.',
            style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _idController,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Student ID',
              hintText: 'e.g. STU_25BCS001',
              errorText: id.isEmpty ? null : idError,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _borderFor(idError, id)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _borderFor(idError, id),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password (online sign-in only)',
              errorText: password.isEmpty ? null : passwordError,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _borderFor(passwordError, password),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _borderFor(passwordError, password),
                  width: 2,
                ),
              ),
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 16),
            Text(_notice!, style: const TextStyle(color: Color(0xFF38BDF8))),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _continueOffline,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_off),
            label: const Text('Continue offline'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _bypassOnlineSignIn,
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('Skip Supabase sign-in'),
          ),
        ],
      ),
    );
  }
}
