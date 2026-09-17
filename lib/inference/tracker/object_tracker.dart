import 'dart:math' as math;
import 'dart:ui';
import '../../models/detection.dart';
import '../../models/tracked_detection.dart';
import '../nms.dart';

class _TrackState {
  final int id;
  Rect normalizedBox;
  Rect pixelBox;
  double confidence;
  int classId;
  String className;
  int age = 1;
  int missedFrames = 0;
  final List<int> classHistory;
  final List<String> classNameHistory;

  _TrackState({
    required this.id,
    required this.normalizedBox,
    required this.pixelBox,
    required this.confidence,
    required this.classId,
    required this.className,
  })  : classHistory = [classId],
        classNameHistory = [className];

  void updateWithDetection(
    Detection detection, {
    double boxAlpha = 0.65,
    double confAlpha = 0.50,
  }) {
    age++;
    missedFrames = 0;

    final Rect newNorm = detection.normalizedBox;
    final double l = normalizedBox.left * (1 - boxAlpha) + newNorm.left * boxAlpha;
    final double t = normalizedBox.top * (1 - boxAlpha) + newNorm.top * boxAlpha;
    final double r = normalizedBox.right * (1 - boxAlpha) + newNorm.right * boxAlpha;
    final double b = normalizedBox.bottom * (1 - boxAlpha) + newNorm.bottom * boxAlpha;
    normalizedBox = Rect.fromLTRB(l, t, r, b);

    final Rect newPix = detection.boundingBox;
    final double pl = pixelBox.left * (1 - boxAlpha) + newPix.left * boxAlpha;
    final double pt = pixelBox.top * (1 - boxAlpha) + newPix.top * boxAlpha;
    final double pr = pixelBox.right * (1 - boxAlpha) + newPix.right * boxAlpha;
    final double pb = pixelBox.bottom * (1 - boxAlpha) + newPix.bottom * boxAlpha;
    pixelBox = Rect.fromLTRB(pl, pt, pr, pb);

    confidence = confidence * (1 - confAlpha) + detection.confidence * confAlpha;

    classHistory.add(detection.classId);
    classNameHistory.add(detection.className);
    if (classHistory.length > 7) {
      classHistory.removeAt(0);
      classNameHistory.removeAt(0);
    }

    final Map<int, int> voteCounts = {};
    for (final cid in classHistory) {
      voteCounts[cid] = (voteCounts[cid] ?? 0) + 1;
    }

    int bestCid = detection.classId;
    int maxVotes = 0;
    for (final entry in voteCounts.entries) {
      if (entry.value > maxVotes) {
        maxVotes = entry.value;
        bestCid = entry.key;
      }
    }

    classId = bestCid;
    final int idx = classHistory.lastIndexOf(bestCid);
    if (idx >= 0 && idx < classNameHistory.length) {
      className = classNameHistory[idx];
    }
  }

  void markMissed() {
    missedFrames++;
    age++;
  }
}

class ObjectTracker {
  final int maxLostFrames;
  final double iouThreshold;
  final double boxAlpha;
  final double confAlpha;

  int _nextTrackId = 1;
  final List<_TrackState> _tracks = [];

  ObjectTracker({
    this.maxLostFrames = 6,
    this.iouThreshold = 0.30,
    this.boxAlpha = 0.65,
    this.confAlpha = 0.50,
  });

  List<TrackedDetection> update(
    List<Detection> rawDetections, {
    int? frameIndex,
  }) {
    if (rawDetections.isEmpty) {
      final List<TrackedDetection> results = [];
      final List<_TrackState> toRemove = [];

      for (final track in _tracks) {
        track.markMissed();
        if (track.missedFrames <= maxLostFrames) {
          final double opacity = math.max(
            0.3,
            1.0 - (track.missedFrames / (maxLostFrames + 1)),
          );
          results.add(
            TrackedDetection(
              classId: track.classId,
              className: track.className,
              confidence: track.confidence,
              boundingBox: track.pixelBox,
              normalizedBox: track.normalizedBox,
              trackId: track.id,
              age: track.age,
              missedFrames: track.missedFrames,
              isLost: true,
              opacity: opacity,
              frameIndex: frameIndex,
            ),
          );
        } else {
          toRemove.add(track);
        }
      }

      for (final dead in toRemove) {
        _tracks.remove(dead);
      }

      return results;
    }

    final int numDetections = rawDetections.length;
    final int numTracks = _tracks.length;

    final List<bool> detectionMatched = List<bool>.filled(numDetections, false);
    final List<bool> trackMatched = List<bool>.filled(numTracks, false);

    if (numTracks > 0) {
      final List<List<double>> iouMatrix = List.generate(
        numTracks,
        (t) => List<double>.filled(numDetections, 0.0),
      );

      for (int t = 0; t < numTracks; t++) {
        final track = _tracks[t];
        for (int d = 0; d < numDetections; d++) {
          final det = rawDetections[d];
          final double iou = Nms.calculateIoU(
            track.normalizedBox.left,
            track.normalizedBox.top,
            track.normalizedBox.right,
            track.normalizedBox.bottom,
            det.normalizedBox.left,
            det.normalizedBox.top,
            det.normalizedBox.right,
            det.normalizedBox.bottom,
          );
          iouMatrix[t][d] = iou;
        }
      }

      while (true) {
        double maxIoU = iouThreshold;
        int bestTrack = -1;
        int bestDet = -1;

        for (int t = 0; t < numTracks; t++) {
          if (trackMatched[t]) continue;
          for (int d = 0; d < numDetections; d++) {
            if (detectionMatched[d]) continue;
            if (iouMatrix[t][d] > maxIoU) {
              maxIoU = iouMatrix[t][d];
              bestTrack = t;
              bestDet = d;
            }
          }
        }

        if (bestTrack != -1 && bestDet != -1) {
          trackMatched[bestTrack] = true;
          detectionMatched[bestDet] = true;
          _tracks[bestTrack].updateWithDetection(
            rawDetections[bestDet],
            boxAlpha: boxAlpha,
            confAlpha: confAlpha,
          );
        } else {
          break;
        }
      }
    }

    for (int t = 0; t < numTracks; t++) {
      if (!trackMatched[t]) {
        _tracks[t].markMissed();
      }
    }

    for (int d = 0; d < numDetections; d++) {
      if (!detectionMatched[d]) {
        final det = rawDetections[d];
        _tracks.add(
          _TrackState(
            id: _nextTrackId++,
            normalizedBox: det.normalizedBox,
            pixelBox: det.boundingBox,
            confidence: det.confidence,
            classId: det.classId,
            className: det.className,
          ),
        );
      }
    }

    _tracks.removeWhere((t) => t.missedFrames > maxLostFrames);

    final List<TrackedDetection> output = [];
    for (final track in _tracks) {
      final bool isLost = track.missedFrames > 0;
      final double opacity = isLost
          ? math.max(0.3, 1.0 - (track.missedFrames / (maxLostFrames + 1)))
          : 1.0;

      output.add(
        TrackedDetection(
          classId: track.classId,
          className: track.className,
          confidence: track.confidence,
          boundingBox: track.pixelBox,
          normalizedBox: track.normalizedBox,
          trackId: track.id,
          age: track.age,
          missedFrames: track.missedFrames,
          isLost: isLost,
          opacity: opacity,
          frameIndex: frameIndex,
        ),
      );
    }

    return output;
  }

  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }
}
