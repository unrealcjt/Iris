import 'package:sqflite/sqflite.dart';
import 'vocabulary_model.dart';
import 'practice_database.dart';

class VocabularyService {
  static final VocabularyService _instance = VocabularyService._internal();
  factory VocabularyService() => _instance;
  VocabularyService._internal();

  final PracticeDatabase _practiceDb = PracticeDatabase();

  Future<Database> get _db async => await _practiceDb.database;

  Future<void> init() async {
    await _db;
  }

  Future<int> addEntry(VocabularyEntry entry) async {
    final db = await _db;
    return await db.insert('vocabulary', entry.toMap());
  }

  Future<List<VocabularyEntry>> getAllEntries() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query('vocabulary', orderBy: 'addTime DESC');
    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  Future<List<VocabularyEntry>> getDueEntries() async {
    final now = DateTime.now().toIso8601String();
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      where: 'reviewTime <= ? AND familiarity > 0',
      whereArgs: [now],
      orderBy: 'reviewTime ASC',
    );
    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  Future<List<VocabularyEntry>> getNewEntries(int limit) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      where: 'familiarity = 0',
      limit: limit,
      orderBy: 'addTime ASC',
    );
    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  Future<List<VocabularyEntry>> getRandomEntries(int limit) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      orderBy: 'RANDOM()',
      limit: limit,
    );
    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  Future<void> resetAllProgress() async {
    final db = await _db;
    await db.update(
      'vocabulary',
      {
        'familiarity': 0,
        'reviewTime': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> updateFamiliarity(int entSeq, int familiarity, DateTime nextReview) async {
    final db = await _db;
    await db.update(
      'vocabulary',
      {
        'familiarity': familiarity,
        'reviewTime': nextReview.toIso8601String(),
      },
      where: 'entSeq = ?',
      whereArgs: [entSeq],
    );
  }

  Future<String> getDatabasePath() async {
    final db = await _db;
    return db.path;
  }

  Future<bool> isCollected(int entSeq) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      where: 'entSeq = ?',
      whereArgs: [entSeq],
    );
    return maps.isNotEmpty;
  }

  Future<void> removeEntry(int entSeq) async {
    final db = await _db;
    await db.delete(
      'vocabulary',
      where: 'entSeq = ?',
      whereArgs: [entSeq],
    );
  }
}
