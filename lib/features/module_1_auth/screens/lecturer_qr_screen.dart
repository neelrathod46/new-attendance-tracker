import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Reads the lecturer server address from either the registration QR or an
/// active attendance QR.
class LecturerQrScreen extends StatefulWidget {
  const LecturerQrScreen({super.key});

  @override
  State<LecturerQrScreen> createState() => _LecturerQrScreenState();
}

class _LecturerQrScreenState extends State<LecturerQrScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;
  String? _error;

  void _handleCapture(BarcodeCapture capture) {
    if (_handling) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    _handling = true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('This is not a lecturer QR code.');
      }
      final serverUrl = decoded['serverUrl']?.toString() ?? '';
      final uri = Uri.tryParse(serverUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '0.0.0.0' ||
          uri.host == '10.0.2.2') {
        throw const FormatException(
          'This QR does not contain a usable lecturer Wi-Fi address.',
        );
      }
      print('[AUTH] Read lecturer address from QR: $serverUrl');
      Navigator.of(context).pop(serverUrl);
    } catch (error) {
      setState(
        () => _error = error.toString().replaceFirst('FormatException: ', ''),
      );
      _handling = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan lecturer QR')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _handleCapture),
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _error ?? 'Point your camera at the registration or class QR.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _error == null ? Colors.white : const Color(0xFFFDA4AF),
              ),
            ),
          ),
        ),
        if (_error != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton.icon(
                onPressed: () => setState(() {
                  _error = null;
                  _handling = false;
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Scan again'),
              ),
            ),
          ),
      ],
    ),
  );
}
