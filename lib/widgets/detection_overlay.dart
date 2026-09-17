import 'package:flutter/material.dart';
import '../models/detection.dart';
import '../models/tracked_detection.dart';
import '../utils/coordinate_utils.dart';

class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final Size sourceImageSize;
  final BoxFit fit;
  final Color primaryColor;
  final Orientation orientation;

  BoundingBoxPainter({
    required this.detections,
    required this.sourceImageSize,
    this.fit = BoxFit.contain,
    this.primaryColor = const Color(0xFF0066FF),
    this.orientation = Orientation.portrait,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final Size effectiveImageSize = (sourceImageSize.isEmpty ||
            sourceImageSize.width <= 0 ||
            sourceImageSize.height <= 0)
        ? size
        : sourceImageSize;

    if (size.isEmpty || size.width <= 0 || size.height <= 0) return;

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];
      final double opacity = (detection is TrackedDetection) ? detection.opacity : 1.0;

      final Rect rawRect = CoordinateUtils.mapNormalizedToView(
        normalizedBox: detection.normalizedBox,
        widgetSize: size,
        imageSize: effectiveImageSize,
        fit: fit,
      );

      final double clampedL = rawRect.left.clamp(0.0, size.width);
      final double clampedT = rawRect.top.clamp(0.0, size.height);
      final double clampedR = rawRect.right.clamp(0.0, size.width);
      final double clampedB = rawRect.bottom.clamp(0.0, size.height);
      final double left = clampedL < clampedR ? clampedL : clampedR;
      final double right = clampedL < clampedR ? clampedR : clampedL;
      final double top = clampedT < clampedB ? clampedT : clampedB;
      final double bottom = clampedT < clampedB ? clampedB : clampedT;
      final Rect viewRect = Rect.fromLTRB(left, top, right, bottom);

      if (viewRect.width <= 2 || viewRect.height <= 2) continue;

      final boxColor = primaryColor;
      final fillPaint = Paint()
        ..color = boxColor.withValues(alpha: 0.12 * opacity)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = boxColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      final RRect roundedBox = RRect.fromRectAndRadius(
        viewRect,
        const Radius.circular(8),
      );
      canvas.drawRRect(roundedBox, fillPaint);
      canvas.drawRRect(roundedBox, strokePaint);

      _drawCornerAccents(canvas, viewRect, boxColor.withValues(alpha: opacity));
      _drawLabelPill(canvas, size, viewRect, detection, boxColor, opacity);
    }
  }

  void _drawCornerAccents(Canvas canvas, Rect rect, Color color) {
    final accentPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final double cornerLen = 14.0;

    canvas.drawLine(rect.topLeft, Offset(rect.left + cornerLen, rect.top), accentPaint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + cornerLen), accentPaint);

    canvas.drawLine(rect.topRight, Offset(rect.right - cornerLen, rect.top), accentPaint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + cornerLen), accentPaint);

    canvas.drawLine(rect.bottomLeft, Offset(rect.left + cornerLen, rect.bottom), accentPaint);
    canvas.drawLine(rect.bottomLeft, Offset(rect.left, rect.bottom - cornerLen), accentPaint);

    canvas.drawLine(rect.bottomRight, Offset(rect.right - cornerLen, rect.bottom), accentPaint);
    canvas.drawLine(rect.bottomRight, Offset(rect.right, rect.bottom - cornerLen), accentPaint);
  }

  void _drawLabelPill(
    Canvas canvas,
    Size canvasSize,
    Rect viewRect,
    Detection detection,
    Color accentColor,
    double opacity,
  ) {
    final String labelText = '${detection.className} ${detection.confidencePercent}';

    final textSpan = TextSpan(
      text: labelText,
      style: TextStyle(
        color: Colors.white.withValues(alpha: opacity),
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    const double paddingH = 8.0;
    const double paddingV = 4.0;
    final double pillWidth = textPainter.width + (paddingH * 2);
    final double pillHeight = textPainter.height + (paddingV * 2);

    const double safeMargin = 6.0;
    double pillX = viewRect.left;
    double pillY = viewRect.top - pillHeight - 4;

    if (pillY < safeMargin) {
      pillY = (viewRect.top + 4).clamp(safeMargin, canvasSize.height - pillHeight - safeMargin);
    }
    if (pillX + pillWidth > canvasSize.width - safeMargin) {
      pillX = canvasSize.width - pillWidth - safeMargin;
    }
    if (pillX < safeMargin) pillX = safeMargin;

    final Rect pillRect = Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight);
    final RRect pillRRect = RRect.fromRectAndRadius(
      pillRect,
      const Radius.circular(6),
    );

    final pillBgPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.90 * opacity)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(pillRRect, pillBgPaint);

    final dotPaint = Paint()
      ..color = accentColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(pillX + 6, pillY + (pillHeight / 2)),
      2.5,
      dotPaint,
    );

    textPainter.paint(
      canvas,
      Offset(pillX + paddingH + 4, pillY + paddingV),
    );
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sourceImageSize != sourceImageSize ||
        oldDelegate.fit != fit ||
        oldDelegate.orientation != orientation;
  }
}

class DetectionOverlay extends StatefulWidget {
  final List<Detection> detections;
  final Size sourceImageSize;
  final BoxFit fit;
  final Orientation orientation;
  final Widget? child;
  final bool enableAnimation;

  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.sourceImageSize,
    this.fit = BoxFit.contain,
    this.orientation = Orientation.portrait,
    this.child,
    this.enableAnimation = false,
  });

  @override
  State<DetectionOverlay> createState() => _DetectionOverlayState();
}

class _DetectionOverlayState extends State<DetectionOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _animController;
  Animation<double>? _animation;

  List<Detection> _prevDetections = [];
  List<Detection> _targetDetections = [];

  @override
  void initState() {
    super.initState();
    _targetDetections = widget.detections;
    _prevDetections = widget.detections;

    if (widget.enableAnimation) {
      _initAnimation();
    }
  }

  void _initAnimation() {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    controller.value = 1.0;
    _animController = controller;
  }

  @override
  void didUpdateWidget(covariant DetectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enableAnimation) {
      _targetDetections = widget.detections;
      return;
    }

    if (_animController == null) {
      _initAnimation();
    }

    if (widget.detections != oldWidget.detections) {
      _prevDetections = _buildInterpolatedDetections(_animation?.value ?? 1.0);
      _targetDetections = widget.detections;
      _animController?.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }

  List<Detection> _buildInterpolatedDetections(double t) {
    if (_targetDetections.isEmpty) {
      if (t >= 1.0) return const [];
      return _prevDetections;
    }

    if (_prevDetections.isEmpty || t >= 1.0) {
      return _targetDetections;
    }

    final List<Detection> interpolated = [];

    for (final target in _targetDetections) {
      Detection? bestMatch;
      double minDistance = double.infinity;

      for (final prev in _prevDetections) {
        if (prev.classId == target.classId) {
          final dist = (prev.normalizedBox.center - target.normalizedBox.center).distance;
          if (dist < minDistance) {
            minDistance = dist;
            bestMatch = prev;
          }
        }
      }

      if (bestMatch != null && minDistance < 0.3) {
        final lerpedBox = Rect.lerp(bestMatch.normalizedBox, target.normalizedBox, t)!;
        final lerpedConfidence =
            bestMatch.confidence + (target.confidence - bestMatch.confidence) * t;

        if (target is TrackedDetection) {
          interpolated.add(
            TrackedDetection(
              classId: target.classId,
              className: target.className,
              confidence: lerpedConfidence,
              boundingBox: target.boundingBox,
              normalizedBox: lerpedBox,
              trackId: target.trackId,
              age: target.age,
              missedFrames: target.missedFrames,
              isLost: target.isLost,
              opacity: target.opacity,
              timestamp: target.timestamp,
              frameIndex: target.frameIndex,
            ),
          );
        } else {
          interpolated.add(
            Detection(
              classId: target.classId,
              className: target.className,
              confidence: lerpedConfidence,
              boundingBox: target.boundingBox,
              normalizedBox: lerpedBox,
              timestamp: target.timestamp,
            ),
          );
        }
      } else {
        interpolated.add(target);
      }
    }

    return interpolated;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enableAnimation || _animation == null) {
      return CustomPaint(
        painter: BoundingBoxPainter(
          detections: widget.detections,
          sourceImageSize: widget.sourceImageSize,
          fit: widget.fit,
          orientation: widget.orientation,
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _animation!,
      builder: (context, child) {
        final currentBoxes = _buildInterpolatedDetections(_animation!.value);
        return CustomPaint(
          painter: BoundingBoxPainter(
            detections: currentBoxes,
            sourceImageSize: widget.sourceImageSize,
            fit: widget.fit,
            orientation: widget.orientation,
          ),
          child: widget.child,
        );
      },
    );
  }
}
