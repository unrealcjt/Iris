import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:Iris/jm/models.dart';

void main() {
  // 1. 初始化 FFI 驱动，这样测试环境才能运行 SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('JMDict 词典探索测试', () {
    late Database db;

    setUpAll(() async {
      // 在所有测试开始前打开数据库
      final dbPath = p.join(Directory.current.path, 'assets', 'jmdict.sqlite');

      // 打印一下，确保你在控制台看到的路径是电脑上真实的物理路径
      print('正在尝试打开数据库: $dbPath');

      // 检查文件是否存在，防止 late 报错
      if (!File(dbPath).existsSync()) {
        fail('错误：在路径 $dbPath 没找到词典文件！请检查路径是否正确。');
      }
      // 注意：单元测试中文件路径是相对于项目根目录的
      db = await openDatabase(dbPath, readOnly: true);
    });

    tearDownAll(() async {
      // 测试结束后关闭
      await db.close();
    });

    test('查看数据库中所有的表名', () async {
      var tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
      );
      print('数据库中的表: $tables');
      expect(tables, isNotEmpty);
    });

    test('获取单词释义和获取汉字读音', () async {
      // 1. 从数据库获取原始 Map 列表
      List<Map<String, dynamic>> results = await db.query('senses', where: 'ent_seq = ?', whereArgs: [1000030]);

      // 2. 转换为 Dart 对象列表
      List<JmSense> senses = results.map((m) => JmSense.fromMap(m)).toList();

      // 3. 访问数据（非常直观）
      for (var s in senses) {
        print('词性: ${s.pos.join(", ")}');
        print('英文释义: ${s.glosses.join("; ")}');
      }

      Map<String, dynamic> kanjiMap = (await db.query('kanji', where: 'literal = ?', whereArgs: ['学'])).first;
      KanjiCharacter char = KanjiCharacter.fromMap(kanjiMap);

      // 提取所有的训读 (ja_kun)
      var kunReadings = char.readingMeaning?.readings
          .where((r) => r.type == 'ja_on')
          .map((r) => r.value);
      print('训读: $kunReadings');
    });

    test('查询“猫”的完整信息（包含所有含义）', () async {
      // 1. 先查词条本体
      final List<Map<String, dynamic>> entryMaps = await db.query(
        'entries',
        where: 'kana LIKE ?',
        whereArgs: ['%\"written\":\"ねこ\"%'], // 注意：因为 kana 是 JSON 字符串，匹配需谨慎
        limit: 1,
      );

      if (entryMaps.isNotEmpty) {
        final entry = JmEntry.fromMap(entryMaps.first);

        // 2. 根据 ent_seq 查所有的 Senses
        final List<Map<String, dynamic>> senseMaps = await db.query(
          'senses',
          where: 'ent_seq = ?',
          whereArgs: [entry.entSeq],
        );

        print('词条 ID: ${entry.entSeq}');
        print('含义数量: ${senseMaps.length}');

        // 3. 解析第一个含义的释义 (glosses)
        var firstSenseGlosses = jsonDecode(senseMaps.first['glosses']);
        print('首个释义: $firstSenseGlosses');
      }
    });
  });
}

class JmEntry {
  final int entSeq;
  final String? _kanjiJson; // 数据库存储的原始 JSON 字符串
  final String _kanaJson;

  JmEntry({
    required this.entSeq,
    String? kanji,
    required String kana,
  })  : _kanjiJson = kanji,
        _kanaJson = kana;

  // 工厂模式：从数据库 Map 转换
  factory JmEntry.fromMap(Map<String, dynamic> map) {
    return JmEntry(
      entSeq: map['ent_seq'],
      kanji: map['kanji'],
      kana: map['kana'],
    );
  }

  // 利用 Getter 实时解析 JSON 为 Dart 对象
  List<Written> get kanji => _kanjiJson != null
      ? (jsonDecode(_kanjiJson!) as List).map((i) => Written.fromJson(i)).toList()
      : [];

  List<Written> get kana =>
      (jsonDecode(_kanaJson) as List).map((i) => Written.fromJson(i)).toList();
}

class Written {
  final String written;
  final List<String>? tags;

  Written({required this.written, this.tags});

  factory Written.fromJson(Map<String, dynamic> json) {
    return Written(
      written: json['written'],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : null,
    );
  }
}