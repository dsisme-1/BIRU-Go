import 'dart:math' as math;
import 'package:flutter/painting.dart';



class LetterboxInfo {
  final double scale;
  final double dx;
  final double dy;
  final int targetWidth;
  final int targetHeight;
  final int originalWidth;
  final int originalHeight;

  const LetterboxInfo({
    required this.scale,
    required this.dx,
    required this.dy,
    required this.targetWidth,
    required this.targetHeight,
    required this.originalWidth,
    required this.originalHeight,
  });
}

class CoordinateUtils {
  static LetterboxInfo computeLetterbox({
    required int originalWidth,
    required int originalHeight,
    int targetWidth = 640,
    int targetHeight = 640,
  }) {
    final double scale = math.min(
      targetWidth / originalWidth,
      targetHeight / originalHeight,
    );
    final double newW = originalWidth * scale;
    final double newH = originalHeight * scale;
    final double dx = (targetWidth - newW) / 2.0;
    final double dy = (targetHeight - newH) / 2.0;

    return LetterboxInfo(
      scale: scale,
      dx: dx,
      dy: dy,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );
  }

  static Rect unletterboxBox({
    required double cxNorm,
    required double cyNorm,
    required double wNorm,
    required double hNorm,
    required LetterboxInfo letterbox,
  }) {
    final double cxCanvas = cxNorm * letterbox.targetWidth;
    final double cyCanvas = cyNorm * letterbox.targetHeight;
    final double wCanvas = wNorm * letterbox.targetWidth;
    final double hCanvas = hNorm * letterbox.targetHeight;

    final double x1Canvas = cxCanvas - (wCanvas / 2.0);
    final double y1Canvas = cyCanvas - (hCanvas / 2.0);
    final double x2Canvas = cxCanvas + (wCanvas / 2.0);
    final double y2Canvas = cyCanvas + (hCanvas / 2.0);

    double x1Orig = (x1Canvas - letterbox.dx) / letterbox.scale;
    double y1Orig = (y1Canvas - letterbox.dy) / letterbox.scale;
    double x2Orig = (x2Canvas - letterbox.dx) / letterbox.scale;
    double y2Orig = (y2Canvas - letterbox.dy) / letterbox.scale;

    x1Orig = x1Orig.clamp(0.0, letterbox.originalWidth.toDouble());
    y1Orig = y1Orig.clamp(0.0, letterbox.originalHeight.toDouble());
    x2Orig = x2Orig.clamp(0.0, letterbox.originalWidth.toDouble());
    y2Orig = y2Orig.clamp(0.0, letterbox.originalHeight.toDouble());

    return Rect.fromLTRB(x1Orig, y1Orig, x2Orig, y2Orig);
  }

  static Rect toNormalizedBox({
    required Rect origRect,
    required int originalWidth,
    required int originalHeight,
  }) {
    if (originalWidth <= 0 || originalHeight <= 0) return Rect.zero;
    return Rect.fromLTRB(
      (origRect.left / originalWidth).clamp(0.0, 1.0),
      (origRect.top / originalHeight).clamp(0.0, 1.0),
      (origRect.right / originalWidth).clamp(0.0, 1.0),
      (origRect.bottom / originalHeight).clamp(0.0, 1.0),
    );
  }

  static Rect mapNormalizedToView({
    required Rect normalizedBox,
    required Size widgetSize,
    required Size imageSize,
    BoxFit fit = BoxFit.contain,
  }) {
    if (widgetSize.isEmpty || imageSize.isEmpty) return Rect.zero;

    double scaleX = 1.0;
    double scaleY = 1.0;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (fit == BoxFit.contain) {
      final double scale = math.min(
        widgetSize.width / imageSize.width,
        widgetSize.height / imageSize.height,
      );
      final double fittedWidth = imageSize.width * scale;
      final double fittedHeight = imageSize.height * scale;

      offsetX = (widgetSize.width - fittedWidth) / 2.0;
      offsetY = (widgetSize.height - fittedHeight) / 2.0;
      scaleX = fittedWidth;
      scaleY = fittedHeight;
    } else if (fit == BoxFit.cover) {
      final double scale = math.max(
        widgetSize.width / imageSize.width,
        widgetSize.height / imageSize.height,
      );
      final double fittedWidth = imageSize.width * scale;
      final double fittedHeight = imageSize.height * scale;

      offsetX = (widgetSize.width - fittedWidth) / 2.0;
      offsetY = (widgetSize.height - fittedHeight) / 2.0;
      scaleX = fittedWidth;
      scaleY = fittedHeight;
    } else {
      scaleX = widgetSize.width;
      scaleY = widgetSize.height;
    }

    return Rect.fromLTRB(
      offsetX + (normalizedBox.left * scaleX),
      offsetY + (normalizedBox.top * scaleY),
      offsetX + (normalizedBox.right * scaleX),
      offsetY + (normalizedBox.bottom * scaleY),
    );
  }
}
