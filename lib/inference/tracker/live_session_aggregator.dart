import '../../models/detection.dart';
import '../../models/detection_summary.dart';
import '../../models/tracked_detection.dart';

class LiveSessionAggregator {
  final int maxDistinctSpecies;
  final int minConfirmedFrames;

  final Map<int, _TrackRecord> _activeTracks = {};
  final Map<int, SpeciesSummary> _recentSpeciesMap = {};

  int _totalFramesProcessed = 0;
  final DateTime _sessionStart = DateTime.now();

  LiveSessionAggregator({
    this.maxDistinctSpecies = 5,
    this.minConfirmedFrames = 2,
  });

  void addFrameDetections(List<Detection> detections) {
    _totalFramesProcessed++;
    final now = DateTime.now();

    for (final det in detections) {
      final int trackId = (det is TrackedDetection) ? det.trackId : det.classId;
      final int age = (det is TrackedDetection) ? det.age : 1;

      var record = _activeTracks[trackId];
      if (record == null) {
        record = _TrackRecord(
          trackId: trackId,
          classId: det.classId,
          speciesName: det.className,
          highestConfidence: det.confidence,
          firstSeen: now,
          lastSeen: now,
          framesSeen: 1,
        );
        _activeTracks[trackId] = record;
      } else {
        record.framesSeen++;
        record.lastSeen = now;
        if (det.confidence > record.highestConfidence) {
          record.highestConfidence = det.confidence;
          record.classId = det.classId;
          record.speciesName = det.className;
        }
      }

      if (record.framesSeen >= minConfirmedFrames || age >= minConfirmedFrames) {
        _recordConfirmedSpecies(record);
      }
    }
  }

  void _recordConfirmedSpecies(_TrackRecord record) {
    final existing = _recentSpeciesMap[record.classId];
    if (existing == null) {
      if (_recentSpeciesMap.length >= maxDistinctSpecies) {
        final oldestKey = _recentSpeciesMap.keys.first;
        _recentSpeciesMap.remove(oldestKey);
      }

      _recentSpeciesMap[record.classId] = SpeciesSummary(
        classId: record.classId,
        speciesName: record.speciesName,
        highestConfidence: record.highestConfidence,
        detectionCount: 1,
        firstDetected: record.firstSeen,
        lastDetected: record.lastSeen,
      );
    } else {
      final double peakConf = record.highestConfidence > existing.highestConfidence
          ? record.highestConfidence
          : existing.highestConfidence;

      _recentSpeciesMap.remove(record.classId);
      _recentSpeciesMap[record.classId] = SpeciesSummary(
        classId: record.classId,
        speciesName: record.speciesName,
        highestConfidence: peakConf,
        detectionCount: existing.detectionCount + 1,
        firstDetected: existing.firstDetected,
        lastDetected: record.lastSeen,
      );
    }
  }

  DetectionSummary buildSummary() {
    final speciesList = _recentSpeciesMap.values.toList().reversed.toList();
    final totalDetections = speciesList.fold<int>(0, (sum, s) => sum + s.detectionCount);

    return DetectionSummary(
      speciesList: speciesList,
      totalDetections: totalDetections,
      totalFramesProcessed: _totalFramesProcessed,
      processingDuration: DateTime.now().difference(_sessionStart),
      source: DetectionSource.liveCamera,
      sessionTimestamp: _sessionStart,
    );
  }

  void reset() {
    _activeTracks.clear();
    _recentSpeciesMap.clear();
    _totalFramesProcessed = 0;
  }
}

class _TrackRecord {
  final int trackId;
  int classId;
  String speciesName;
  double highestConfidence;
  final DateTime firstSeen;
  DateTime lastSeen;
  int framesSeen;

  _TrackRecord({
    required this.trackId,
    required this.classId,
    required this.speciesName,
    required this.highestConfidence,
    required this.firstSeen,
    required this.lastSeen,
    required this.framesSeen,
  });
}
