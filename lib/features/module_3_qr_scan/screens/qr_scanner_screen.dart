import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/qr_payload.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/token_validation_card.dart';

/// Standalone QR Camera Scanner & Token Inspector (Module 3)
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _scannerController;
  final Set<int> _usedNonces = {};

  QrPayload? _latestPayload;
  bool _isProcessing = false;
  bool _torchActive = false;
  CameraFacing _currentFacing = CameraFacing.back;

  @override
  void initState() {
    super.initState();
    print('[QR_SCAN] Initializing MobileScannerController...');
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: _currentFacing,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    print('[QR_SCAN] Disposing MobileScannerController...');
    _scannerController.dispose();
    super.dispose();
  }

  void _handleBarcodeCapture(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final first = barcodes.first;
    final rawValue = first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    print('[QR_SCAN] Frame captured: rawValue=$rawValue');

    setState(() {
      _isProcessing = true;
    });

    _processQrString(rawValue);
  }

  void _processQrString(String raw) {
    final payload = QrPayload.parse(raw, usedNonces: _usedNonces);

    print(
      '[QR_SCAN] Parsed token: session=${payload.session}, '
      'nonce=${payload.nonce}, ts=${payload.timestamp}, '
      'age=${payload.ageMs}ms, status=${payload.status}, '
      'message="${payload.statusMessage}"',
    );

    // If valid, register nonce in local session memory to prevent replay attacks
    if (payload.isValid && payload.nonce != 0) {
      _usedNonces.add(payload.nonce);
      print('[QR_SCAN] Registered nonce #${payload.nonce} in active session cache.');
    }

    setState(() {
      _latestPayload = payload;
    });
  }

  void _resumeScanning() {
    print('[QR_SCAN] Resuming active camera viewfinder...');
    setState(() {
      _latestPayload = null;
      _isProcessing = false;
    });
  }

  void _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
      setState(() {
        _torchActive = !_torchActive;
      });
      print('[QR_SCAN] Torch toggled: $_torchActive');
    } catch (e) {
      print('[QR_SCAN] Torch toggle failed: $e');
    }
  }

  void _switchCamera() async {
    try {
      await _scannerController.switchCamera();
      setState(() {
        _currentFacing = _currentFacing == CameraFacing.back
            ? CameraFacing.front
            : CameraFacing.back;
      });
      print('[QR_SCAN] Camera switched to: $_currentFacing');
    } catch (e) {
      print('[QR_SCAN] Camera switch failed: $e');
    }
  }

  // Quick simulation injector for immediate verification
  void _injectSimulatedToken({required int ageOffsetMs, bool duplicateNonce = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final simulatedTs = now - ageOffsetMs;
    final nonce = duplicateNonce && _usedNonces.isNotEmpty
        ? _usedNonces.last
        : 100000 + (now % 900000);

    final simulatedJson = jsonEncode({
      'session': 'CS101',
      'nonce': nonce,
      'ts': simulatedTs,
    });

    print('[QR_SCAN] Injecting simulated token: $simulatedJson');
    _processQrString(simulatedJson);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanBoxSize = (size.width * 0.72).clamp(240.0, 320.0);
    final scanWindow = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: scanBoxSize,
      height: scanBoxSize,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Module 3: QR Scanner',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Anti-Proxy 2.0s Hard Limit Inspector',
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF38BDF8).withOpacity(0.9),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _torchActive ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchActive ? const Color(0xFFFBBF24) : Colors.white70,
            ),
            tooltip: 'Toggle Flashlight',
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white70),
            tooltip: 'Flip Camera',
            onPressed: _switchCamera,
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Simulate Token Payloads',
            onPressed: _showSimulationDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Live Camera Preview Feed
          MobileScanner(
            controller: _scannerController,
            scanWindow: scanWindow,
            onDetect: _handleBarcodeCapture,
            errorBuilder: (context, error) {
              print('[QR_SCAN] Camera error: ${error.errorCode}');
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_off_rounded,
                        color: Color(0xFFEF4444),
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Camera Error: ${error.errorCode.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please verify camera permissions or test using the simulation buttons.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _showSimulationDialog,
                        icon: const Icon(Icons.science_rounded),
                        label: const Text('Open Test Simulator'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0369A1),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // 2. Viewfinder Overlay with Animated Sweeping Laser
          ScannerOverlay(scanWindow: scanWindow),

          // 3. Instruction Pill at the top
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_scanner, color: Color(0xFF38BDF8), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Point camera at dynamic QR code on projector',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Live On-Screen Validation Card
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _latestPayload != null
                  ? TokenValidationCard(
                      payload: _latestPayload!,
                      onDismiss: _resumeScanning,
                      onProceedToLiveness: () {
                        print('[QR_SCAN] Token accepted! Moving to Module 4 (Face Liveness)...');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF22C55E),
                            content: Text(
                              'Verified Token CS101 (#${_latestPayload!.nonce})! Ready for Module 4 (Face Liveness).',
                            ),
                          ),
                        );
                      },
                    )
                  : _buildAwaitingScannerHint(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingScannerHint() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Viewfinder Active • Waiting for QR',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          InkWell(
            onTap: _showSimulationDialog,
            child: const Text(
              'Simulate',
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSimulationDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Simulate QR Scan Payloads',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Test anti-proxy validation rules without needing a physical projector screen:',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _injectSimulatedToken(ageOffsetMs: 400); // 400ms old (Fresh)
                  },
                  icon: const Icon(Icons.check_circle, color: Color(0xFF22C55E)),
                  label: const Text('Fresh Valid Token (Generated 400ms ago)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    side: const BorderSide(color: Color(0xFF22C55E)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _injectSimulatedToken(ageOffsetMs: 3200); // 3.2s old (Expired)
                  },
                  icon: const Icon(Icons.error, color: Color(0xFFEF4444)),
                  label: const Text('Expired Token (Generated 3.2s ago - Rejected)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _injectSimulatedToken(ageOffsetMs: 500, duplicateNonce: true);
                  },
                  icon: const Icon(Icons.replay, color: Color(0xFFF59E0B)),
                  label: const Text('Replay Attack (Resend same nonce token)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _processQrString("https://example.com/fake-url");
                  },
                  icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  label: const Text('Malformed Payload (Invalid QR)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
