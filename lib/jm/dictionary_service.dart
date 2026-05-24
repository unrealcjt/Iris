import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:Iris/jm/models.dart'; // 导入之前定义的模型

class DictionaryService {
  Database? _db;

  // 单例模式，确保整个 App 只打开一个数据库连接
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  DictionaryService._internal();

  /// 初始化数据库：处理移动端 Assets 拷贝与 FFI 环境适配
  Future<void> init() async {
    if (_db != null) return;

    String path;
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动端路径处理
      var databasesPath = await getDatabasesPath();
      path = join(databasesPath, "jmdict.sqlite");

      if (!(await databaseExists(path))) {
        // 第一次启动，从 Assets 拷贝
        ByteData data = await rootBundle.load("assets/jmdict.sqlite");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }
      _db = await openDatabase(path, readOnly: true);
    } else {
      // 单元测试/桌面端路径处理
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      path = join(Directory.current.path, 'assets', 'jmdict.sqlite');
      _db = await openDatabase(path, readOnly: true);
    }
  }

  /// 接口 1: 搜索单词 (通过平假名或片假名)
  /// 由于 kana 是 JSON 字符串 [ {"written": "..."} ]，使用 LIKE 匹配
  Future<List<JmEntry>> searchEntries(String query) async {
    final List<Map<String, dynamic>> maps = await _db!.query(
      'entries',
      where: 'kana LIKE ? OR kanji LIKE ?',
      whereArgs: ['%\"written\":\"$query\"%', '%\"written\":\"$query\"%'],
      limit: 20,
    );
    // print("原始搜索命中的数据: ${maps.first['kanji']}");
    return maps.map((m) => JmEntry.fromMap(m)).toList();
  }

  /// 接口 2: 获取单词详情 (包含所有的 Senses)
  Future<List<JmSense>> getSensesByEntSeq(int entSeq) async {
    final List<Map<String, dynamic>> maps = await _db!.query(
      'senses',
      where: 'ent_seq = ?',
      whereArgs: [entSeq],
      orderBy: 'sort_order ASC',
    );
    return maps.map((m) => JmSense.fromMap(m)).toList();
  }

  /// 接口 3: 获取汉字信息 (Kanjidic)
  Future<KanjiCharacter?> getKanjiInfo(String char) async {
    final List<Map<String, dynamic>> maps = await _db!.query(
      'kanji',
      where: 'literal = ?',
      whereArgs: [char],
    );
    if (maps.isEmpty) return null;
    return KanjiCharacter.fromMap(maps.first);
  }

  /// 接口 4: 模糊搜索 (适用于搜索框联想)
  Future<List<String>> getSuggestions(String pattern) async {
    if (pattern.isEmpty) return [];

    try {
      final List<Map<String, dynamic>> maps = await _db!.query(
        'entries',
        columns: ['kanji', 'kana'],
        // 稍微放宽 limit 范围，这样我们能在内存中进行更好的排序
        where: 'kanji LIKE ? OR kana LIKE ?',
        whereArgs: ['%$pattern%', '%$pattern%'],
        limit: 50,
      );

      // 使用两个 Set，一个放精确匹配，一个放模糊匹配，方便最后合并排序
      Set<String> exactMatches = {};
      Set<String> startWithMatches = {};
      Set<String> containsMatches = {};

      for (var row in maps) {
        final String kanjiJson = row['kanji'] as String? ?? '[]';
        final String kanaJson = row['kana'] as String? ?? '[]';

        // 统一处理函数
        void processJson(String jsonStr) {
          final List<dynamic> data = jsonDecode(jsonStr);
          for (var item in data) {
            String w = item['written'] as String? ?? '';
            if (w == pattern) {
              exactMatches.add(w); // 完全一样（如：输入“猫”，搜到“猫”）
            } else if (w.startsWith(pattern)) {
              startWithMatches.add(w); // 开头匹配（如：输入“猫”，搜到“猫舌”）
            } else if (w.contains(pattern)) {
              containsMatches.add(w); // 包含匹配（如：输入“猫”，搜到“野良猫”）
            }
          }
        }

        processJson(kanjiJson);
        processJson(kanaJson);

        // 如果已经攒够了足够多的精确和开头匹配，就提前结束
        if (exactMatches.length + startWithMatches.length >= 10) break;
      }

      // 按优先级合并结果：精确匹配 > 开头匹配 > 包含匹配
      return [
        ...exactMatches,
        ...startWithMatches,
        ...containsMatches,
      ].take(10).toList();

    } catch (e) {
      print("联想查询出错: $e");
      return [];
    }
  }
}