import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../module_5_embedding/models/enrollment_profile.dart';
import '../../module_5_embedding/screens/face_verification_screen.dart';
import '../models/liveness_result.dart';

/// A deliberate, user-visible three-frame liveness challenge. ML Kit supplies
/// the face/eye/smile signals; identity matching is deferred to Module 5.
class LivenessScreen extends StatefulWidget {
  final EnrollmentProfile? enrollment;

  const LivenessScreen({super.key, required this.enrollment});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> {
  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.20,
    ),
  );
  CameraController? _camera;
  var _loading = true;
  var _busy = false;
  var _step = 0;
  double? _openEyes;
  double? _blinkEyes;
  double? _smile;
  String? _finalImagePath;
  FaceBounds? _finalFaceBounds;
  String? _error;

  static const _steps = ['Keep both eyes open', 'Blink naturally', 'Smile'];

  @override
  void initState() {
    super.initState();
    // Liveness proves presence, not identity. Avoid activating the camera until
    // Module 1 has supplied the authenticated student's enrolled reference.
    if (widget.enrollment == null) {
      _loading = false;
      _error = 'Face enrollment is required before identity verification can begin.';
      return;
    }
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      final camera = front.isNotEmpty ? front.first : cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _loading = false;
      });
      print('[LIVENESS] Front camera initialized.');
    } catch (error) {
      print('[LIVENESS] Camera initialization failed: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Camera unavailable: $error';
        });
      }
    }
  }

  Future<void> _captureChallengeFrame() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await camera.takePicture();
      final faces = await _detector.processImage(
        InputImage.fromFilePath(image.path),
      );
      if (faces.length != 1) {
        throw StateError('Show exactly one face in the oval before capturing.');
      }
      final face = faces.single;
      final leftEye = face.leftEyeOpenProbability;
      final rightEye = face.rightEyeOpenProbability;
      final eyeAverage = leftEye != null && rightEye != null
          ? (leftEye + rightEye) / 2
          : null;
      final smile = face.smilingProbability;

      if (_step == 0 && (eyeAverage == null || eyeAverage < .70)) {
        throw StateError('Both eyes must be clearly open for the first frame.');
      }
      if (_step == 1 && (eyeAverage == null || eyeAverage > .35)) {
        throw StateError('Blink, then capture while your eyes are closed.');
      }
      if (_step == 2 && (smile == null || smile < .55)) {
        throw StateError('Please smile clearly, then try again.');
      }

      print('[LIVENESS] Step $_step accepted: eye=$eyeAverage smile=$smile');
      setState(() {
        if (_step == 0) _openEyes = eyeAverage;
        if (_step == 1) _blinkEyes = eyeAverage;
        if (_step == 2) {
          _smile = smile;
          _finalImagePath = image.path;
          _finalFaceBounds = FaceBounds(
            left: face.boundingBox.left,
            top: face.boundingBox.top,
            width: face.boundingBox.width,
            height: face.boundingBox.height,
          );
        }
        _step += 1;
      });
      if (_step == _steps.length) _continueToVerification();
    } catch (error) {
      print('[LIVENESS] Challenge frame rejected: $error');
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueToVerification() async {
    final imagePath = _finalImagePath;
    final faceBounds = _finalFaceBounds;
    if (imagePath == null || faceBounds == null || !mounted) return;
    final result = LivenessResult(
      imagePath: imagePath,
      faceBounds: faceBounds,
      openEyesProbability: _openEyes!,
      blinkEyesProbability: _blinkEyes!,
      smileProbability: _smile!,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaceVerificationScreen(
          enrollment: widget.enrollment,
          liveness: result,
        ),
      ),
    );
  }

  @override
  void dispose() {
    print('[LIVENESS] Releasing camera and ML Kit detector.');
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instruction = _step < _steps.length
        ? _steps[_step]
        : 'Liveness passed';
    return Scaffold(
      appBar: AppBar(title: const Text('Module 4: Face Liveness')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _camera == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? 'Camera unavailable'),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_camera!),
                      Center(
                        child: Container(
                          width: 230,
                          height: 300,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF38BDF8),
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(140),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Step ${_step + 1} of 3 · $instruction',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Three distinct captures prevent a static photo from passing.',
                        textAlign: TextAlign.center,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFEF4444)),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _captureChallengeFrame,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Text(
                          _busy ? 'Checking…' : 'Capture $instruction',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
