import 'dart:math' as math;
import '../models/detection.dart';

class Nms {
  static double calculateIoU(
    double leftA,
    double topA,
    double rightA,
    double bottomA,
    double leftB,
    double topB,
    double rightB,
    double bottomB,
  ) {
    final double intersectLeft = math.max(leftA, leftB);
    final double intersectTop = math.max(topA, topB);
    final double intersectRight = math.min(rightA, rightB);
    final double intersectBottom = math.min(bottomA, bottomB);

    final double intersectWidth = math.max(0.0, intersectRight - intersectLeft);
    final double intersectHeight = math.max(0.0, intersectBottom - intersectTop);
    final double intersectionArea = intersectWidth * intersectHeight;

    if (intersectionArea <= 0.0) return 0.0;

    final double areaA = (rightA - leftA) * (bottomA - topA);
    final double areaB = (rightB - leftB) * (bottomB - topB);
    final double unionArea = areaA + areaB - intersectionArea;

    if (unionArea <= 0.0) return 0.0;
    return intersectionArea / unionArea;
  }

  static List<Detection> applyNms(
    List<Detection> detections, {
    double iouThreshold = 0.45,
    int maxDetections = 50,
  }) {
    if (detections.isEmpty) return [];

    final List<Detection> candidates = List<Detection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<Detection> selected = [];
    final List<bool> suppressed = List<bool>.filled(candidates.length, false);

    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;

      final current = candidates[i];
      selected.add(current);
      if (selected.length >= maxDetections) break;

      for (int j = i + 1; j < candidates.length; j++) {
        if (suppressed[j]) continue;

        final candidate = candidates[j];
        final double iou = calculateIoU(
          current.boundingBox.left,
          current.boundingBox.top,
          current.boundingBox.right,
          current.boundingBox.bottom,
          candidate.boundingBox.left,
          candidate.boundingBox.top,
          candidate.boundingBox.right,
          candidate.boundingBox.bottom,
        );

        if (iou > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return selected;
  }
}
