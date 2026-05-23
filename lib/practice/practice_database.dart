import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PracticeDatabase {
  static final PracticeDatabase _instance = PracticeDatabase._internal();
  factory PracticeDatabase() => _instance;
  PracticeDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    String databasesPath;
    if (Platform.isAndroid || Platform.isIOS) {
      databasesPath = await getDatabasesPath();
    } else {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      databasesPath = Directory.current.path;
    }
    
    String path = join(databasesPath, "practice.sqlite");
    String oldPath = join(databasesPath, "vocabulary.sqlite");

    // Simple migration: if old db exists and new doesn't, rename it
    if (await File(oldPath).exists() && !await File(path).exists()) {
      await File(oldPath).copy(path);
      // Optional: await File(oldPath).delete(); 
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createVocabularyTable(db);
        await _createGrammarTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createGrammarTable(db);
        }
      },
    );
  }

  Future<void> _createVocabularyTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vocabulary (
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
  }

  Future<void> _createGrammarTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grammar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        meaning TEXT,
        structure TEXT,
        examples TEXT,
        addTime TEXT,
        note TEXT,
        tags TEXT
      )
    ''');
  }
}
