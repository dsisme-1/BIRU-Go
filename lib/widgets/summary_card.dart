import 'package:flutter/material.dart';
import '../models/detection_summary.dart';
import 'confidence_badge.dart';

class SummaryCard extends StatelessWidget {
  final DetectionSummary summary;

  const SummaryCard({
    super.key,
    required this.summary,
  });

  IconData _getSourceIcon(DetectionSource source) {
    switch (source) {
      case DetectionSource.liveCamera:
        return Icons.videocam_rounded;
      case DetectionSource.localVideo:
        return Icons.movie_filter_outlined;
      case DetectionSource.photoGallery:
        return Icons.photo_library_outlined;
    }
  }

  Color _getSourceColor(DetectionSource source) {
    switch (source) {
      case DetectionSource.liveCamera:
        return const Color(0xFF0066FF);
      case DetectionSource.localVideo:
        return const Color(0xFF6366F1);
      case DetectionSource.photoGallery:
        return const Color(0xFF0284C7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color sourceColor = _getSourceColor(summary.source);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: sourceColor.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getSourceIcon(summary.source),
                    color: sourceColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            summary.sourceTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: summary.speciesList.isNotEmpty
                                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                  : const Color(0xFF64748B).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              summary.speciesList.isNotEmpty
                                  ? '${summary.speciesList.length} Species'
                                  : '0 Birds',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: summary.speciesList.isNotEmpty
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${summary.formattedDate} • ${summary.formattedTime}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (summary.speciesList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(27),
                      ),
                      child: const Icon(
                        Icons.search_off_rounded,
                        color: Color(0xFF94A3B8),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No Birds Detected',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ensure the bird is clearly visible and well-lit, or adjust the confidence threshold.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: summary.speciesList.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                color: Color(0xFFF1F5F9),
                indent: 20,
                endIndent: 20,
              ),
              itemBuilder: (context, index) {
                final item = summary.speciesList[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.flutter_dash,
                          size: 18,
                          color: Color(0xFF0066FF),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.speciesName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.detectionCount} ${item.detectionCount == 1 ? 'detection' : 'detections'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConfidenceBadge(confidence: item.highestConfidence),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
