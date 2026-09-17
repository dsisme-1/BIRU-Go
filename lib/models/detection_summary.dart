import 'dart:convert';
import 'detection.dart';

enum DetectionSource {
  liveCamera,
  photoGallery,
  localVideo,
}

class SpeciesSummary {
  final int classId;
  final String speciesName;
  final double highestConfidence;
  final int detectionCount;
  final DateTime firstDetected;
  final DateTime lastDetected;

  SpeciesSummary({
    required this.classId,
    required this.speciesName,
    required this.highestConfidence,
    required this.detectionCount,
    required this.firstDetected,
    required this.lastDetected,
  });

  String get highestConfidencePercent =>
      '${(highestConfidence * 100).toStringAsFixed(1)}%';

  Map<String, dynamic> toJson() => {
        'classId': classId,
        'speciesName': speciesName,
        'highestConfidence': highestConfidence,
        'detectionCount': detectionCount,
        'firstDetected': firstDetected.millisecondsSinceEpoch,
        'lastDetected': lastDetected.millisecondsSinceEpoch,
      };

  factory SpeciesSummary.fromJson(Map<String, dynamic> json) => SpeciesSummary(
        classId: json['classId'] as int,
        speciesName: json['speciesName'] as String,
        highestConfidence: (json['highestConfidence'] as num).toDouble(),
        detectionCount: json['detectionCount'] as int,
        firstDetected:
            DateTime.fromMillisecondsSinceEpoch(json['firstDetected'] as int),
        lastDetected:
            DateTime.fromMillisecondsSinceEpoch(json['lastDetected'] as int),
      );
}

class DetectionSummary {
  final int? id;
  final List<SpeciesSummary> speciesList;
  final int totalDetections;
  final int totalFramesProcessed;
  final Duration processingDuration;
  final DetectionSource source;
  final DateTime sessionTimestamp;
  final String? imagePath;
  final Map<int, List<Detection>> timelineCache;

  DetectionSummary({
    this.id,
    required this.speciesList,
    required this.totalDetections,
    this.totalFramesProcessed = 1,
    this.processingDuration = Duration.zero,
    this.source = DetectionSource.photoGallery,
    DateTime? sessionTimestamp,
    this.imagePath,
    this.timelineCache = const {},
  }) : sessionTimestamp = sessionTimestamp ?? DateTime.now();

  DetectionSummary copyWith({
    int? id,
    List<SpeciesSummary>? speciesList,
    int? totalDetections,
    int? totalFramesProcessed,
    Duration? processingDuration,
    DetectionSource? source,
    DateTime? sessionTimestamp,
    String? imagePath,
    Map<int, List<Detection>>? timelineCache,
  }) {
    return DetectionSummary(
      id: id ?? this.id,
      speciesList: speciesList ?? this.speciesList,
      totalDetections: totalDetections ?? this.totalDetections,
      totalFramesProcessed: totalFramesProcessed ?? this.totalFramesProcessed,
      processingDuration: processingDuration ?? this.processingDuration,
      source: source ?? this.source,
      sessionTimestamp: sessionTimestamp ?? this.sessionTimestamp,
      imagePath: imagePath ?? this.imagePath,
      timelineCache: timelineCache ?? this.timelineCache,
    );
  }

  Map<String, dynamic> toDbMap() {
    final topSpecies = speciesList.isNotEmpty ? speciesList.first.speciesName : 'None';
    final topConfidence = speciesList.isNotEmpty ? speciesList.first.highestConfidence : 0.0;
    final speciesJson = jsonEncode(speciesList.map((s) => s.toJson()).toList());

    return {
      if (id != null) 'id': id,
      'session_timestamp': sessionTimestamp.millisecondsSinceEpoch,
      'source': source.name,
      'total_detections': totalDetections,
      'species_list_json': speciesJson,
      'image_path': imagePath,
      'top_species': topSpecies,
      'top_confidence': topConfidence,
    };
  }

  factory DetectionSummary.fromDbMap(Map<String, dynamic> map) {
    final int? dbId = map['id'] as int?;
    final int ts = map['session_timestamp'] as int;
    final String srcStr = map['source'] as String;
    final int totalDets = map['total_detections'] as int;
    final String speciesJson = map['species_list_json'] as String;
    final String? imgPath = map['image_path'] as String?;

    DetectionSource src = DetectionSource.photoGallery;
    if (srcStr == 'liveCamera') {
      src = DetectionSource.liveCamera;
    } else if (srcStr == 'localVideo') {
      src = DetectionSource.localVideo;
    }

    List<SpeciesSummary> parsedSpecies = [];
    try {
      final decoded = jsonDecode(speciesJson) as List<dynamic>;
      parsedSpecies = decoded
          .map((item) => SpeciesSummary.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    return DetectionSummary(
      id: dbId,
      speciesList: parsedSpecies,
      totalDetections: totalDets,
      source: src,
      sessionTimestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      imagePath: imgPath,
    );
  }

  static const List<String> _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  String get formattedDate {
    final d = sessionTimestamp;
    final monthName = _monthsEn[d.month - 1];
    return '${d.day} $monthName ${d.year}';
  }

  String get formattedTime {
    final d = sessionTimestamp;
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get sourceTitle {
    switch (source) {
      case DetectionSource.liveCamera:
        return 'Live Camera';
      case DetectionSource.localVideo:
        return 'Local Video';
      case DetectionSource.photoGallery:
        return 'Photo & Gallery';
    }
  }

  factory DetectionSummary.fromDetections(
    List<Detection> detections, {
    int totalFrames = 1,
    Duration duration = Duration.zero,
    DetectionSource source = DetectionSource.photoGallery,
    DateTime? sessionTimestamp,
    Map<int, List<Detection>> timelineCache = const {},
  }) {
    final Map<int, List<Detection>> grouped = {};
    for (final d in detections) {
      grouped.putIfAbsent(d.classId, () => []).add(d);
    }

    final List<SpeciesSummary> summaries = [];
    for (final entry in grouped.entries) {
      final list = entry.value;
      list.sort((a, b) => b.confidence.compareTo(a.confidence));
      final top = list.first;

      summaries.add(
        SpeciesSummary(
          classId: entry.key,
          speciesName: top.className,
          highestConfidence: top.confidence,
          detectionCount: list.length,
          firstDetected: list.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b),
          lastDetected: list.map((e) => e.timestamp).reduce((a, b) => a.isAfter(b) ? a : b),
        ),
      );
    }

    summaries.sort((a, b) => b.highestConfidence.compareTo(a.highestConfidence));

    return DetectionSummary(
      speciesList: summaries,
      totalDetections: detections.length,
      totalFramesProcessed: totalFrames,
      processingDuration: duration,
      source: source,
      sessionTimestamp: sessionTimestamp,
      timelineCache: timelineCache,
    );
  }
}
