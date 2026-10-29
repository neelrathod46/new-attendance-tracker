import 'dart:io';

import 'package:flutter/material.dart';

import '../../module_1_auth/models/student_session.dart';
import '../../module_3_qr_scan/models/face_verification_result.dart';
import '../../module_3_qr_scan/screens/qr_scanner_screen.dart';
import '../../module_4_liveness/models/liveness_result.dart';
import '../services/face_embedding_service.dart';
import '../widgets/embedding_vector_grid.dart';

/// Converts the liveness capture into an embedding and opens Module 3 only when
/// it matches the authenticated student's enrolled 192-d reference vector.
class FaceVerificationScreen extends StatefulWidget {
  final StudentSession session;
  final LivenessResult liveness;

  const FaceVerificationScreen({
    super.key,
    required this.session,
    required this.liveness,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  final _embeddingService = FaceEmbeddingService();
  FaceVerificationResult? _result;
  List<double>? _capturedEmbedding;
  String? _error;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final enrollment = widget.session.enrollment;
    if (enrollment == null) {
      setState(
        () => _error = 'No enrolled face is available. Complete authenticated enrollment before checking attendance.',
      );
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      print('[FACE_VERIFY] Creating embedding for ${enrollment.studentId}.');
      final capturedEmbedding = await _embeddingService.createEmbedding(
        widget.liveness,
      );
      final distance = FaceEmbeddingService.euclideanDistance(
        capturedEmbedding,
        enrollment.embedding,
      );
      final result = FaceVerificationResult(
        livenessPassed: true,
        identityMatched: distance <= FaceVerificationResult.matchThreshold,
        embeddingDistance: distance,
        studentId: enrollment.studentId,
        verifiedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      print(
        '[FACE_VERIFY] Euclidean distance=${distance.toStringAsFixed(4)}, matched=${result.identityMatched}.',
      );
      if (mounted) {
        setState(() {
          _capturedEmbedding = capturedEmbedding;
          _result = result;
        });
      }
    } catch (error) {
      print('[FACE_VERIFY] Verification failed: $error');
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      await _deleteCapture();
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _deleteCapture() async {
    try {
      await File(widget.liveness.imagePath).delete();
    } catch (_) {}
  }

  void _openScanner(FaceVerificationResult result) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          verification: result,
          session: widget.session,
          verificationEmbedding: _capturedEmbedding,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  void dispose() {
    _embeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final matched = result?.isVerified == true;
    final captured = _capturedEmbedding;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your identity')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _checking
                    ? Icons.fingerprint_rounded
                    : matched
                    ? Icons.verified_user_rounded
                    : Icons.face_retouching_off_rounded,
                size: 72,
                color: _checking
                    ? const Color(0xFF38BDF8)
                    : matched
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
              ),
              const SizedBox(height: 20),
              Text(
                _checking
                    ? 'Matching your face…'
                    : matched
                    ? 'You’re verified'
                    : 'We couldn’t confirm your face',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _checking
                    ? 'Comparing this live capture with your registered face.'
                    : matched
                    ? 'Your face matches the enrollment on your student profile.'
                    : 'Try again facing the camera in clear, even lighting.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), height: 1.45),
              ),
              if (result != null || captured != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Technical verification details',
                      style: TextStyle(fontSize: 12),
                    ),
                    children: [
                      Text(
                        'Liveness signals · eyes ${widget.liveness.openEyesProbability.toStringAsFixed(2)} · blink ${widget.liveness.blinkEyesProbability.toStringAsFixed(2)} · smile ${widget.liveness.smileProbability.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                      if (result != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Embedding distance: ${result.embeddingDistance.toStringAsFixed(4)} / ${FaceVerificationResult.matchThreshold.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: matched
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444),
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (captured != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: EmbeddingVectorGrid(values: captured),
                        ),
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFEF4444)),
                ),
              ],
              const SizedBox(height: 24),
              if (_checking)
                const CircularProgressIndicator()
              else if (matched)
                FilledButton.icon(
                  onPressed: () => _openScanner(result!),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Continue to class code'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry liveness'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
