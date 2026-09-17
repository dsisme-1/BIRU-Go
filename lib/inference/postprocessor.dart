import 'dart:typed_data';
import 'dart:ui';
import '../models/detection.dart';
import '../utils/coordinate_utils.dart';
import 'nms.dart';

class YoloPostprocessor {
  static const int defaultNumAnchors = 2100;
  static const int numAttributes = 559;
  static const int numClasses = 555;

  double confidenceThreshold;
  double nmsThreshold;

  YoloPostprocessor({
    this.confidenceThreshold = 0.35,
    this.nmsThreshold = 0.45,
  });

  List<Detection> process({
    required Float32List rawOutput,
    required LetterboxInfo letterboxInfo,
    required List<String> classNames,
    int? numAnchors,
    int? frameIndex,
  }) {
    final List<Detection> candidateDetections = [];

    final int resolvedAnchors = numAnchors ??
        (rawOutput.length >= numAttributes
            ? rawOutput.length ~/ numAttributes
            : defaultNumAnchors);
    final int step = resolvedAnchors;
    final int classStartOffset = 4 * step;
    final Float32List maxScores = Float32List(resolvedAnchors);
    final Int32List bestClasses = Int32List(resolvedAnchors);
    bestClasses.fillRange(0, resolvedAnchors, -1);

    for (int c = 0; c < numClasses; c++) {
      final int rowOffset = classStartOffset + c * step;
      for (int a = 0; a < resolvedAnchors; a++) {
        final double score = rawOutput[rowOffset + a];
        if (score > maxScores[a]) {
          maxScores[a] = score;
          bestClasses[a] = c;
        }
      }
    }

    for (int anchor = 0; anchor < resolvedAnchors; anchor++) {
      final double maxClassScore = maxScores[anchor];
      final int bestClassId = bestClasses[anchor];

      if (maxClassScore < confidenceThreshold || bestClassId < 0) {
        continue;
      }

      final double cxNorm = rawOutput[anchor];
      final double cyNorm = rawOutput[step + anchor];
      final double wNorm = rawOutput[(step << 1) + anchor];
      final double hNorm = rawOutput[step * 3 + anchor];

      final Rect origBox = CoordinateUtils.unletterboxBox(
        cxNorm: cxNorm,
        cyNorm: cyNorm,
        wNorm: wNorm,
        hNorm: hNorm,
        letterbox: letterboxInfo,
      );

      if (origBox.width <= 2 || origBox.height <= 2) continue;

      final Rect normalizedBox = CoordinateUtils.toNormalizedBox(
        origRect: origBox,
        originalWidth: letterboxInfo.originalWidth,
        originalHeight: letterboxInfo.originalHeight,
      );

      final String name = (bestClassId < classNames.length)
          ? classNames[bestClassId]
          : 'Bird #$bestClassId';

      candidateDetections.add(
        Detection(
          classId: bestClassId,
          className: name,
          confidence: maxClassScore,
          boundingBox: origBox,
          normalizedBox: normalizedBox,
          frameIndex: frameIndex,
        ),
      );
    }

    return Nms.applyNms(
      candidateDetections,
      iouThreshold: nmsThreshold,
      maxDetections: 50,
    );
  }
}
