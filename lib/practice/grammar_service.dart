import 'package:sqflite/sqflite.dart';
import 'grammar_model.dart';
import 'practice_database.dart';

class GrammarService {
  static final GrammarService _instance = GrammarService._internal();
  factory GrammarService() => _instance;
  GrammarService._internal();

  final PracticeDatabase _practiceDb = PracticeDatabase();

  Future<Database> get _db async => await _practiceDb.database;

  Future<int> addEntry(GrammarEntry entry) async {
    final db = await _db;
    return await db.insert('grammar', entry.toMap());
  }

  Future<List<GrammarEntry>> getAllEntries() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query('grammar', orderBy: 'addTime DESC');
    return maps.map((m) => GrammarEntry.fromMap(m)).toList();
  }

  Future<List<GrammarEntry>> searchGrammar(String query) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'grammar',
      where: 'title LIKE ? OR meaning LIKE ? OR structure LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'addTime DESC',
    );
    return maps.map((m) => GrammarEntry.fromMap(m)).toList();
  }

  Future<void> removeEntry(int id) async {
    final db = await _db;
    await db.delete(
      'grammar',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateEntry(GrammarEntry entry) async {
    final db = await _db;
    await db.update(
      'grammar',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }
}
