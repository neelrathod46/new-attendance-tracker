import 'dart:io';

import 'package:flutter/material.dart';

import '../../module_1_auth/models/student_session.dart';
import '../../module_4_liveness/models/liveness_result.dart';
import '../models/enrollment_profile.dart';
import '../services/face_embedding_service.dart';
import '../widgets/embedding_vector_grid.dart';

/// Turns a passed liveness capture into the on-device reference vector.
class EnrollmentReviewScreen extends StatefulWidget {
  final StudentSession session;
  final LivenessResult liveness;

  const EnrollmentReviewScreen({
    super.key,
    required this.session,
    required this.liveness,
  });

  @override
  State<EnrollmentReviewScreen> createState() => _EnrollmentReviewScreenState();
}

class _EnrollmentReviewScreenState extends State<EnrollmentReviewScreen> {
  final _embeddingService = FaceEmbeddingService();
  List<double>? _embedding;
  String? _error;
  var _working = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      print(
        '[ENROLL] Creating reference embedding for ${widget.session.studentId}.',
      );
      final embedding = await _embeddingService.createEmbedding(
        widget.liveness,
      );
      if (mounted) setState(() => _embedding = embedding);
    } catch (error) {
      print('[ENROLL] Embedding failed: $error');
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      await _deleteCapture();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteCapture() async {
    try {
      await File(widget.liveness.imagePath).delete();
    } catch (_) {}
  }

  void _save() {
    final embedding = _embedding;
    if (embedding == null) return;
    widget.session.enrollment = EnrollmentProfile(
      studentId: widget.session.studentId,
      embedding: embedding,
    );
    print('[ENROLL] Saved in-memory profile for ${widget.session.studentId}.');
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pop();
  }

  @override
  void dispose() {
    _embeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final embedding = _embedding;
    return Scaffold(
      appBar: AppBar(title: const Text('Module 5: Face Enrollment')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'This vector stays on the phone. Supabase enrollment upload is skipped.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 20),
          if (_working) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
          if (embedding != null) EmbeddingVectorGrid(values: embedding),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: embedding == null || _working ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save locally (skip cloud upload)'),
          ),
        ],
      ),
    );
  }
}
