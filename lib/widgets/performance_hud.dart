import 'package:flutter/material.dart';
import '../models/detection.dart';
import 'confidence_badge.dart';

class PerformanceHud extends StatefulWidget {
  final double currentFps;
  final List<Detection> recentDetections;
  final bool initialExpanded;

  const PerformanceHud({
    super.key,
    required this.currentFps,
    this.recentDetections = const [],
    this.initialExpanded = false,
  });

  @override
  State<PerformanceHud> createState() => _PerformanceHudState();
}

class _PerformanceHudState extends State<PerformanceHud> {
  late bool _expanded = widget.initialExpanded;

  @override
  Widget build(BuildContext context) {
    final Map<int, Detection> uniqueMap = {};
    for (final d in widget.recentDetections) {
      final existing = uniqueMap[d.classId];
      if (existing == null || d.confidence > existing.confidence) {
        uniqueMap[d.classId] = d;
      }
    }
    final List<Detection> topFive = uniqueMap.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final displayList = topFive.take(5).toList();

    return Container(
      margin: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'FPS: ${widget.currentFps.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (displayList.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0066FF).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${displayList.length} species',
                        style: const TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: displayList.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Awaiting bird detections...',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Detected Species',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...displayList.map(
                          (det) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    det.className,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ConfidenceBadge(
                                  confidence: det.confidence,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
