import 'package:flutter/material.dart';

import '../../module_3_qr_scan/models/face_verification_result.dart';
import '../../module_3_qr_scan/screens/qr_scanner_screen.dart';
import '../../module_4_liveness/models/liveness_result.dart';
import '../models/enrollment_profile.dart';
import '../services/face_embedding_service.dart';

/// Converts the liveness capture into an embedding and opens Module 3 only when
/// it matches the authenticated student's enrolled 128-d reference vector.
class FaceVerificationScreen extends StatefulWidget {
  final EnrollmentProfile? enrollment;
  final LivenessResult liveness;

  const FaceVerificationScreen({
    super.key,
    required this.enrollment,
    required this.liveness,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  final _embeddingService = FaceEmbeddingService();
  FaceVerificationResult? _result;
  String? _error;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final enrollment = widget.enrollment;
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
      final distance = FaceEmbeddingService.cosineDistance(
        capturedEmbedding,
        enrollment.embedding,
      );
      final result = FaceVerificationResult(
        livenessPassed: true,
        identityMatched: distance < FaceVerificationResult.matchThreshold,
        cosineDistance: distance,
        studentId: enrollment.studentId,
        verifiedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      print(
        '[FACE_VERIFY] Distance=${distance.toStringAsFixed(4)}, matched=${result.identityMatched}.',
      );
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (error) {
      print('[FACE_VERIFY] Verification failed: $error');
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Module 5: Identity Verification')),
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
                    ? 'Comparing face embedding…'
                    : matched
                    ? 'Identity confirmed'
                    : 'Identity not verified',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Liveness signals: eyes open ${widget.liveness.openEyesProbability.toStringAsFixed(2)}, blink ${widget.liveness.blinkEyesProbability.toStringAsFixed(2)}, smile ${widget.liveness.smileProbability.toStringAsFixed(2)}.',
                textAlign: TextAlign.center,
              ),
              if (result != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Cosine distance: ${result.cosineDistance.toStringAsFixed(4)} / ${FaceVerificationResult.matchThreshold.toStringAsFixed(2)} maximum',
                  style: TextStyle(
                    color: matched
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
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
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(verification: result),
                    ),
                    (route) => false,
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Unlock QR Scanner'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _verify,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
