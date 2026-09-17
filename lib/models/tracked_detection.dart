import 'detection.dart';

class TrackedDetection extends Detection {
  final int trackId;
  final int age;
  final int missedFrames;
  final bool isLost;
  final double opacity;

  TrackedDetection({
    required super.classId,
    required super.className,
    required super.confidence,
    required super.boundingBox,
    required super.normalizedBox,
    required this.trackId,
    required this.age,
    this.missedFrames = 0,
    this.isLost = false,
    this.opacity = 1.0,
    super.timestamp,
    super.frameIndex,
  });

  factory TrackedDetection.fromDetection({
    required Detection detection,
    required int trackId,
    required int age,
    int missedFrames = 0,
    bool isLost = false,
    double opacity = 1.0,
  }) {
    return TrackedDetection(
      classId: detection.classId,
      className: detection.className,
      confidence: detection.confidence,
      boundingBox: detection.boundingBox,
      normalizedBox: detection.normalizedBox,
      trackId: trackId,
      age: age,
      missedFrames: missedFrames,
      isLost: isLost,
      opacity: opacity,
      timestamp: detection.timestamp,
      frameIndex: detection.frameIndex,
    );
  }

  @override
  String toString() {
    return 'TrackedDetection(#$trackId, $className, $confidencePercent, isLost: $isLost, age: $age)';
  }
}
