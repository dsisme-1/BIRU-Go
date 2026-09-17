import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/detection_summary.dart';

class ExportRecord {
  final int? id;
  final String filePath;
  final String fileName;
  final String fileHash;
  final String sourceType;
  final String speciesSummary;
  final double confidenceScore;
  final DateTime timestamp;

  ExportRecord({
    this.id,
    required this.filePath,
    required this.fileName,
    required this.fileHash,
    required this.sourceType,
    required this.speciesSummary,
    required this.confidenceScore,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'file_name': fileName,
      'file_hash': fileHash,
      'source_type': sourceType,
      'species_summary': speciesSummary,
      'confidence_score': confidenceScore,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ExportRecord.fromMap(Map<String, dynamic> map) {
    return ExportRecord(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      fileHash: map['file_hash'] as String,
      sourceType: map['source_type'] as String,
      speciesSummary: map['species_summary'] as String,
      confidenceScore: (map['confidence_score'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  final ValueNotifier<int> sessionsVersionNotifier = ValueNotifier<int>(0);

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('biru_exports.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE export_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_hash TEXT NOT NULL,
        source_type TEXT NOT NULL,
        species_summary TEXT NOT NULL,
        confidence_score REAL NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_file_hash ON export_records(file_hash)');
    await _createSessionTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSessionTable(db);
    }
  }

  Future<void> _createSessionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS detection_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_timestamp INTEGER NOT NULL,
        source TEXT NOT NULL,
        total_detections INTEGER NOT NULL,
        species_list_json TEXT NOT NULL,
        image_path TEXT,
        top_species TEXT NOT NULL,
        top_confidence REAL NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_session_timestamp ON detection_sessions(session_timestamp DESC)',
    );
  }

  static String computeHash(Uint8List bytes) {
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  Future<int> insertSession(DetectionSummary summary, {String? imagePath}) async {
    final db = await database;
    final map = summary.toDbMap();
    if (imagePath != null) {
      map['image_path'] = imagePath;
    }
    final int id = await db.insert(
      'detection_sessions',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    sessionsVersionNotifier.value++;
    return id;
  }

  Future<List<DetectionSummary>> getAllSessions({DetectionSource? filterSource}) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;
    if (filterSource != null) {
      whereClause = 'source = ?';
      whereArgs = [filterSource.name];
    }

    final result = await db.query(
      'detection_sessions',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'session_timestamp DESC',
    );
    return result.map((e) => DetectionSummary.fromDbMap(e)).toList();
  }

  Future<int> deleteSession(int id) async {
    final db = await database;
    final count = await db.delete(
      'detection_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    sessionsVersionNotifier.value++;
    return count;
  }

  Future<int> clearAllSessions() async {
    final db = await database;
    final count = await db.delete('detection_sessions');
    sessionsVersionNotifier.value++;
    return count;
  }

  Future<int> updateSessionImagePath(int id, String imagePath) async {
    final db = await database;
    final count = await db.update(
      'detection_sessions',
      {'image_path': imagePath},
      where: 'id = ?',
      whereArgs: [id],
    );
    sessionsVersionNotifier.value++;
    return count;
  }

  Future<bool> isAlreadyExported(String fileHash) async {
    final db = await database;
    final result = await db.query(
      'export_records',
      where: 'file_hash = ?',
      whereArgs: [fileHash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> isPathExported(String filePath) async {
    final db = await database;
    final result = await db.query(
      'export_records',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<int> insertExport(ExportRecord record) async {
    final db = await database;
    return await db.insert(
      'export_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ExportRecord>> getAllExports() async {
    final db = await database;
    final result = await db.query('export_records', orderBy: 'timestamp DESC');
    return result.map((e) => ExportRecord.fromMap(e)).toList();
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
