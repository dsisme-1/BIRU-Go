import 'dart:ui';

class Detection {
  final int classId;
  final String className;
  final double confidence;
  final Rect boundingBox;
  final Rect normalizedBox;
  final DateTime timestamp;
  final int? frameIndex;

  Detection({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.boundingBox,
    required this.normalizedBox,
    DateTime? timestamp,
    this.frameIndex,
  }) : timestamp = timestamp ?? DateTime.now();

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  @override
  String toString() {
    return 'Detection($className, $confidencePercent, bbox: $boundingBox)';
  }
}
