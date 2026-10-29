import 'package:flutter/material.dart';

/// Animated camera viewfinder overlay with scanning reticle and moving laser sweep
class ScannerOverlay extends StatefulWidget {
  final Rect scanWindow;

  const ScannerOverlay({
    super.key,
    required this.scanWindow,
  });

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ScannerOverlayPainter(
            scanWindow: widget.scanWindow,
            laserProgress: _animationController.value,
          ),
        );
      },
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final double laserProgress;

  _ScannerOverlayPainter({
    required this.scanWindow,
    required this.laserProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    const cornerRadius = Radius.circular(16);
    final rrect = RRect.fromRectAndRadius(scanWindow, cornerRadius);

    // 1. Draw dimmed semi-transparent background around viewfinder
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()
      ..addRect(screenRect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(backgroundPath, backgroundPaint);

    // 2. Draw border frame
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // 3. Draw high-contrast corner brackets
    final cornerPaint = Paint()
      ..color = const Color(0xFF38BDF8) // Sky blue / cyan accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const cornerLength = 28.0;

    // Top-Left
    canvas.drawLine(
      Offset(scanWindow.left, scanWindow.top + cornerLength),
      Offset(scanWindow.left, scanWindow.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanWindow.left, scanWindow.top),
      Offset(scanWindow.left + cornerLength, scanWindow.top),
      cornerPaint,
    );

    // Top-Right
    canvas.drawLine(
      Offset(scanWindow.right - cornerLength, scanWindow.top),
      Offset(scanWindow.right, scanWindow.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanWindow.right, scanWindow.top),
      Offset(scanWindow.right, scanWindow.top + cornerLength),
      cornerPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(scanWindow.left, scanWindow.bottom - cornerLength),
      Offset(scanWindow.left, scanWindow.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanWindow.left, scanWindow.bottom),
      Offset(scanWindow.left + cornerLength, scanWindow.bottom),
      cornerPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(scanWindow.right - cornerLength, scanWindow.bottom),
      Offset(scanWindow.right, scanWindow.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanWindow.right, scanWindow.bottom),
      Offset(scanWindow.right, scanWindow.bottom - cornerLength),
      cornerPaint,
    );

    // 4. Draw moving laser scan line
    final laserY = scanWindow.top + (scanWindow.height * laserProgress);
    final laserGradient = LinearGradient(
      colors: [
        const Color(0xFF38BDF8).withOpacity(0.0),
        const Color(0xFF38BDF8).withOpacity(0.9),
        const Color(0xFF38BDF8).withOpacity(0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final laserPaint = Paint()
      ..shader = laserGradient.createShader(
        Rect.fromLTWH(scanWindow.left, laserY - 1, scanWindow.width, 2),
      )
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(scanWindow.left + 8, laserY),
      Offset(scanWindow.right - 8, laserY),
      laserPaint,
    );

    // 5. Draw laser glow
    final glowPaint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(
        scanWindow.left + 4,
        laserY - 16,
        scanWindow.width - 8,
        32,
      ),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.laserProgress != laserProgress ||
        oldDelegate.scanWindow != scanWindow;
  }
}
