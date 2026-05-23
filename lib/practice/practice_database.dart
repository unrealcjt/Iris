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

  Future<Map<String, int>> importData(String externalDbPath) async {
    Database externalDb = await openDatabase(externalDbPath);
    Database currentDb = await database;

    int vocabImported = 0;
    int grammarImported = 0;

    // Import Vocabulary
    try {
      List<Map<String, dynamic>> externalVocab = await externalDb.query('vocabulary');
      if (externalVocab.isNotEmpty) {
        await currentDb.transaction((txn) async {
          // 获取当前所有已有的 entSeq 提高查询效率
          final List<Map<String, dynamic>> existingRows = await txn.query('vocabulary', columns: ['entSeq']);
          final Set<int> existingEntSeqs = existingRows.map((r) => r['entSeq'] as int).toSet();

          for (var row in externalVocab) {
            final entSeq = row['entSeq'] as int;
            if (!existingEntSeqs.contains(entSeq)) {
              Map<String, dynamic> toInsert = Map.from(row);
              toInsert.remove('id'); // 让当前数据库分配新 ID
              await txn.insert('vocabulary', toInsert);
              vocabImported++;
              existingEntSeqs.add(entSeq); // 防止导入文件中本身有重复
            }
          }
        });
      }
    } catch (e) {
      print("Error importing vocabulary: $e");
    }

    // Import Grammar
    try {
      List<Map<String, dynamic>> externalGrammar = await externalDb.query('grammar');
      if (externalGrammar.isNotEmpty) {
        await currentDb.transaction((txn) async {
          // 获取现有文法进行去重判断
          final List<Map<String, dynamic>> existingRows = await txn.query('grammar', columns: ['title', 'meaning']);
          final Set<String> existingKeys = existingRows.map((r) => "${r['title']}_${r['meaning']}").toSet();

          for (var row in externalGrammar) {
            final String key = "${row['title']}_${row['meaning']}";
            if (!existingKeys.contains(key)) {
              Map<String, dynamic> toInsert = Map.from(row);
              toInsert.remove('id');
              await txn.insert('grammar', toInsert);
              grammarImported++;
              existingKeys.add(key);
            }
          }
        });
      }
    } catch (e) {
      print("Error importing grammar: $e");
    }

    await externalDb.close();
    return {'vocabulary': vocabImported, 'grammar': grammarImported};
  }
}
