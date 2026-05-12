import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'vocabulary_model.dart';

class VocabularyService {
  Database? _db;

  static final VocabularyService _instance = VocabularyService._internal();
  factory VocabularyService() => _instance;
  VocabularyService._internal();

  Future<void> init() async {
    if (_db != null) return;

    String path;
    if (Platform.isAndroid || Platform.isIOS) {
      var databasesPath = await getDatabasesPath();
      path = join(databasesPath, "vocabulary.sqlite");
    } else {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      path = join(Directory.current.path, 'vocabulary.sqlite');
    }

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vocabulary (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entSeq INTEGER,
            word TEXT,
            kana TEXT,
            addTime TEXT,
            familiarity INTEGER DEFAULT 0,
            reviewTime TEXT,
            note TEXT,
            tags TEXT
          )
        ''');
      },
    );
  }

  Future<int> addEntry(VocabularyEntry entry) async {
    return await _db!.insert('vocabulary', entry.toMap());
  }

  Future<List<VocabularyEntry>> getAllEntries() async {
    final List<Map<String, dynamic>> maps = await _db!.query('vocabulary', orderBy: 'addTime DESC');
    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  Future<bool> isCollected(int entSeq) async {
    final List<Map<String, dynamic>> maps = await _db!.query(
      'vocabulary',
      where: 'entSeq = ?',
      whereArgs: [entSeq],
    );
    return maps.isNotEmpty;
  }

  Future<void> removeEntry(int entSeq) async {
    await _db!.delete(
      'vocabulary',
      where: 'entSeq = ?',
      whereArgs: [entSeq],
    );
  }
}
