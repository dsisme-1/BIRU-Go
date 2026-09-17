import 'package:flutter/material.dart';

class ConfidenceBadge extends StatelessWidget {
  final double confidence;
  final bool compact;

  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.compact = false,
  });

  Color _getBadgeColor() {
    if (confidence >= 0.80) {
      return const Color(0xFF0066FF);
    } else if (confidence >= 0.50) {
      return const Color(0xFF0284C7);
    } else {
      return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getBadgeColor();
    final percentStr = '${(confidence * 100).toStringAsFixed(1)}%';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            percentStr,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 13,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
