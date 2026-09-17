import 'package:flutter/material.dart';
import '../models/detection.dart';
import 'confidence_badge.dart';

class DetectionCard extends StatelessWidget {
  final Detection detection;
  final int index;
  final VoidCallback? onTap;

  const DetectionCard({
    super.key,
    required this.detection,
    this.index = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0066FF).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.flutter_dash,
                    size: 20,
                    color: Color(0xFF0066FF),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    detection.className,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConfidenceBadge(confidence: detection.confidence),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
