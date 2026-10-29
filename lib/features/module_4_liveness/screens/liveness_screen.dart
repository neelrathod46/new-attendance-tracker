import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../module_1_auth/models/student_session.dart';
import '../../module_5_embedding/screens/enrollment_review_screen.dart';
import '../../module_5_embedding/screens/face_verification_screen.dart';
import '../camera_frame_converter.dart';
import '../models/liveness_mode.dart';
import '../models/liveness_result.dart';

/// Tracks an open → blink → open → smile sequence from live camera frames.
class LivenessScreen extends StatefulWidget {
  final StudentSession session;
  final LivenessMode mode;

  const LivenessScreen({super.key, required this.session, required this.mode});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> {
  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.20,
    ),
  );

  CameraController? _camera;
  CameraDescription? _description;
  bool _loading = true;
  bool _processingFrame = false;
  bool _finishing = false;
  bool _faceVisible = false;
  bool _blinkFlash = false;
  int _stage = 0;
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  double? _leftEye;
  double? _rightEye;
  double? _smile;
  double? _openEyesScore;
  double? _blinkEyesScore;
  String? _error;

  bool get _isEnroll => widget.mode == LivenessMode.enroll;

  static const _instructions = [
    'Look at the camera with both eyes open',
    'Close your eyes briefly',
    'Open your eyes again',
    'Smile at the camera',
  ];

  @override
  void initState() {
    super.initState();
    if (!_isEnroll && widget.session.enrollment == null) {
      _loading = false;
      _error = 'Enroll your face before starting identity verification.';
    } else {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (mounted) setState(() => _loading = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera is available.');
      final frontCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      final description = frontCameras.isNotEmpty
          ? frontCameras.first
          : cameras.first;
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _description = description;
      _camera = controller;
      _resetChallenge();
      await controller.startImageStream(_processFrame);
      print('[LIVENESS] Live camera stream started mode=${widget.mode.name}.');
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      print('[LIVENESS] Camera initialization failed: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not start the face camera: $error';
        });
      }
    }
  }

  void _resetChallenge() {
    _stage = 0;
    _faceVisible = false;
    _blinkFlash = false;
    _leftEye = null;
    _rightEye = null;
    _smile = null;
    _openEyesScore = null;
    _blinkEyesScore = null;
    _error = null;
    _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _processFrame(CameraImage image) async {
    final controller = _camera;
    final description = _description;
    final now = DateTime.now();
    if (controller == null ||
        description == null ||
        _processingFrame ||
        _finishing ||
        now.difference(_lastFrameTime).inMilliseconds < 180) {
      return;
    }
    _processingFrame = true;
    _lastFrameTime = now;
    try {
      final input = cameraFrameToInputImage(
        image,
        description,
        controller.value.deviceOrientation,
      );
      final faces = await _detector.processImage(input);
      if (faces.length != 1) {
        if (_faceVisible && mounted) {
          setState(() {
            _faceVisible = false;
            _stage = 0;
            _leftEye = null;
            _rightEye = null;
            _smile = null;
            _openEyesScore = null;
            _blinkEyesScore = null;
            _blinkFlash = false;
          });
        }
        return;
      }

      final face = faces.single;
      final left = face.leftEyeOpenProbability;
      final right = face.rightEyeOpenProbability;
      final smile = face.smilingProbability;
      if (!mounted) return;
      setState(() {
        _faceVisible = true;
        _leftEye = left;
        _rightEye = right;
        _smile = smile;
        _error = null;
      });

      if (left == null || right == null) return;
      final eyes = (left + right) / 2;
      if (_stage == 0 && eyes >= 0.70) {
        setState(() {
          _openEyesScore = eyes;
          _stage = 1;
        });
        print(
          '[LIVENESS] Eyes-open baseline detected: ${eyes.toStringAsFixed(2)}',
        );
      } else if (_stage == 1 && eyes <= 0.30) {
        setState(() {
          _blinkEyesScore = eyes;
          _stage = 2;
        });
        print('[LIVENESS] Blink closure detected: ${eyes.toStringAsFixed(2)}');
      } else if (_stage == 2 && eyes >= 0.70) {
        setState(() {
          _blinkFlash = true;
          _stage = 3;
        });
        print('[LIVENESS] Blink completed.');
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _blinkFlash = false);
          }),
        );
      } else if (_stage == 3 && smile != null && smile >= 0.60) {
        setState(() => _stage = 4);
        print('[LIVENESS] Smile challenge passed: ${smile.toStringAsFixed(2)}');
        await _finishChallenge();
      }
    } catch (error) {
      print('[LIVENESS] Frame processing failed: $error');
      if (mounted && !_finishing) {
        setState(() => _error = 'Could not read camera frame: $error');
      }
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _finishChallenge() async {
    if (_finishing) return;
    _finishing = true;
    final controller = _camera;
    if (controller == null) {
      _finishing = false;
      return;
    }

    String? imagePath;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final picture = await controller.takePicture();
      imagePath = picture.path;
      // Use coordinates from the same still image that the embedding service
      // will crop. Live-frame bounds can use a different rotation/scale.
      final stillFaces = await _detector.processImage(
        InputImage.fromFilePath(picture.path),
      );
      if (stillFaces.length != 1) {
        throw StateError(
          'Keep one face centered while the final image is taken.',
        );
      }
      final stillFace = stillFaces.single;
      final openEyes = _openEyesScore;
      final blinkEyes = _blinkEyesScore;
      final smile = stillFace.smilingProbability ?? _smile;
      if (openEyes == null || blinkEyes == null || smile == null) {
        throw StateError('Liveness scores are incomplete. Please try again.');
      }
      final result = LivenessResult(
        imagePath: picture.path,
        faceBounds: FaceBounds(
          left: stillFace.boundingBox.left,
          top: stillFace.boundingBox.top,
          width: stillFace.boundingBox.width,
          height: stillFace.boundingBox.height,
        ),
        openEyesProbability: openEyes,
        blinkEyesProbability: blinkEyes,
        smileProbability: smile,
      );
      await _releaseCamera();
      if (!mounted) {
        await _deleteImage(imagePath);
        return;
      }
      final nextScreen = _isEnroll
          ? EnrollmentReviewScreen(session: widget.session, liveness: result)
          : FaceVerificationScreen(session: widget.session, liveness: result);
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => nextScreen));
      if (!mounted) return;
      _finishing = false;
      await _initializeCamera();
    } catch (error) {
      print('[LIVENESS] Final capture failed: $error');
      await _deleteImage(imagePath);
      await _releaseCamera();
      if (mounted) {
        setState(() {
          _finishing = false;
          _loading = false;
          _error = error.toString().replaceFirst('Bad state: ', '');
          _stage = 0;
        });
        await _initializeCamera();
      }
    }
  }

  Future<void> _deleteImage(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (error) {
      print('[LIVENESS] Temporary image cleanup failed: $error');
    }
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    _description = null;
    if (camera == null) return;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } catch (_) {}
    await camera.dispose();
  }

  @override
  void dispose() {
    print('[LIVENESS] Releasing camera stream and ML Kit detector.');
    final camera = _camera;
    if (camera != null) {
      if (camera.value.isStreamingImages) unawaited(camera.stopImageStream());
      unawaited(camera.dispose());
    }
    unawaited(_detector.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEnroll ? 'Enroll your face' : 'Live identity check';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _camera == null
          ? _buildCameraError()
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_camera!),
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 230,
                          height: 300,
                          decoration: BoxDecoration(
                            color: _blinkFlash
                                ? const Color(0x4422C55E)
                                : Colors.transparent,
                            border: Border.all(
                              color: _blinkFlash
                                  ? const Color(0xFF22C55E)
                                  : _faceVisible
                                  ? const Color(0xFF38BDF8)
                                  : const Color(0xFFEF4444),
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(140),
                          ),
                          child: _blinkFlash
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF22C55E),
                                  size: 56,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 20,
                        right: 20,
                        child: _statusPill(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _stage >= 4
                            ? 'Liveness passed'
                            : _instructions[_stage.clamp(0, 3).toInt()],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _probabilityMeter('Left eye open', _leftEye),
                      _probabilityMeter('Right eye open', _rightEye),
                      _probabilityMeter('Smile', _smile),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFEF4444)),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Live face signals are checked on this phone. No face image is uploaded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCameraError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? 'Camera unavailable', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _initializeCamera,
            icon: const Icon(Icons.refresh),
            label: const Text('Try camera again'),
          ),
        ],
      ),
    ),
  );

  Widget _statusPill() {
    final label = !_faceVisible
        ? 'Center one face in the oval'
        : 'Step ${(_stage + 1).clamp(1, 4)} of 4';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xDD0F172A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _probabilityMeter(String label, double? value) {
    final normalized = (value ?? 0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: normalized,
                minHeight: 8,
                backgroundColor: const Color(0xFF334155),
                valueColor: AlwaysStoppedAnimation<Color>(
                  value == null
                      ? const Color(0xFF64748B)
                      : const Color(0xFF38BDF8),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              value == null ? '—' : '${(normalized * 100).round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
