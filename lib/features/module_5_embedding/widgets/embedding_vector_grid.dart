import 'package:flutter/material.dart';

/// On-screen inspector for the supplied 192-d MobileFaceNet vector.
class EmbeddingVectorGrid extends StatelessWidget {
  final List<double> values;

  const EmbeddingVectorGrid({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '192-d embedding (${values.length} values)',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < values.length; i++)
                Tooltip(
                  message: '[$i] ${values[i].toStringAsFixed(4)}',
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _colorFor(values[i]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Color _colorFor(double value) {
    final t = ((value + 1) / 2).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF0EA5E9), const Color(0xFF22C55E), t)!;
  }
}
