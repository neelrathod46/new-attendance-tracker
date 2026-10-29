import 'dart:async';

import 'package:flutter/material.dart';

import '../models/qr_payload.dart';

/// Interactive on-screen Validation Card with live visual feedback,
/// green/red status banners, and real-time age calculation.
class TokenValidationCard extends StatefulWidget {
  final QrPayload payload;
  final VoidCallback onDismiss;

  const TokenValidationCard({
    super.key,
    required this.payload,
    required this.onDismiss,
  });

  @override
  State<TokenValidationCard> createState() => _TokenValidationCardState();
}

class _TokenValidationCardState extends State<TokenValidationCard> {
  late int _currentElapsedMs;
  Timer? _tickerTimer;
  bool _showRawJson = false;

  @override
  void initState() {
    super.initState();
    _currentElapsedMs = widget.payload.ageMs;
    // Tick every 50ms to give smooth visual feedback of token age
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted && widget.payload.timestamp > 0) {
        setState(() {
          _currentElapsedMs =
              DateTime.now().millisecondsSinceEpoch - widget.payload.timestamp;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant TokenValidationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload.timestamp != widget.payload.timestamp) {
      _currentElapsedMs = widget.payload.ageMs;
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final bool isValid = payload.isValid;

    final Color primaryColor = isValid
        ? const Color(0xFF22C55E) // Bright Green
        : const Color(0xFFEF4444); // Bright Red

    final Color bgColor = const Color(0xFF1E293B); // Dark slate

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.2),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Validation Banner (Green for Valid / Red for Expired/Invalid)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    payload.statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // 2. Token Inspector Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Session & Nonce Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfoBadge(
                      label: 'SESSION',
                      value: payload.session,
                      badgeColor: const Color(0xFF0369A1),
                    ),
                    _buildInfoBadge(
                      label: 'NONCE',
                      value: payload.nonce == 0 ? 'N/A' : '#${payload.nonce}',
                      badgeColor: const Color(0xFF475569),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Live Age / Hard Limit Meter
                if (payload.timestamp > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Live Token Age:',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        '${(_currentElapsedMs / 1000.0).toStringAsFixed(2)}s  /  3.00s max',
                        style: TextStyle(
                          color: _currentElapsedMs <= 3000
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_currentElapsedMs / 3000.0).clamp(0.0, 1.0),
                      backgroundColor: const Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _currentElapsedMs <= 3000
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Anti-Proxy Rule Status Details
                _buildDetailRow(
                  icon: Icons.timer_outlined,
                  label: 'Server Timestamp',
                  value: payload.timestamp == 0
                      ? 'Invalid'
                      : DateTime.fromMillisecondsSinceEpoch(payload.timestamp)
                            .toIso8601String()
                            .split('T')
                            .last
                            .replaceAll('Z', ''),
                ),
                _buildDetailRow(
                  icon: Icons.security_rounded,
                  label: 'Replay Protection',
                  value: switch (payload.status) {
                    TokenValidationStatus.replayAttack =>
                      'DUPLICATE NONCE REJECTED',
                    TokenValidationStatus.staleToken =>
                      'SUPERSEDED CODE REJECTED',
                    _ => 'Nonce Active',
                  },
                  valueColor:
                      payload.status == TokenValidationStatus.replayAttack ||
                          payload.status == TokenValidationStatus.staleToken
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E),
                ),
                const SizedBox(height: 8),

                // Collapsible Raw JSON Inspector
                InkWell(
                  onTap: () {
                    setState(() {
                      _showRawJson = !_showRawJson;
                    });
                  },
                  child: Row(
                    children: [
                      Icon(
                        _showRawJson
                            ? Icons.arrow_drop_down_rounded
                            : Icons.arrow_right_rounded,
                        color: const Color(0xFF38BDF8),
                      ),
                      Text(
                        _showRawJson ? 'Hide Raw JSON' : 'Inspect Raw JSON',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showRawJson) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Text(
                      payload.rawJson,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onDismiss,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF475569)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Scan Again'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge({
    required String label,
    required String value,
    required Color badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
