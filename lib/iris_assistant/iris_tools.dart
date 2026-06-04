import 'dart:convert';

import 'package:Iris/utils/edge_tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jm/dictionary_service.dart';
import '../practice/vocabulary_model.dart';
import '../practice/vocabulary_service.dart';

/// Iris 助手可用的函数工具定义类
class IrisTools {
  /// 技能加载工具
  static const Tool load_skill = Tool(
    name: 'load_skill',
    description: 'Select the required skills from the skill list and load the specific details of the skills.',
    parameters: {
      'type': 'object',
      'properties': {
        'skill_name': {
          'type': 'string',
          'description': 'The name of skill',
        },
      },
      'required': ['skill_name'],
    },
  );
  /// 通用技能调用
  static const Tool run_intent = Tool(
    name: "run_intent",
    description: "The intent that need to be accomplished",
    parameters: {
      'type': 'object',
      'properties': {
        'intent': {
          'type': 'string',
          'description': 'The name of the intent to execute (e.g., speak, searchWeb, addVocabulary, getRandomVocab)',
        },
        'parameters': {
          'type': 'string',
          'description': 'Fill in the specific json parameters according to the skill description you have loaded.'
        }
      },
      'required': ['intent', 'parameters'],
    },
  );
  /// Js工具参数
  static const Tool run_js = Tool(
    name: "run_js",
    description: "The javascript that need to called",
    parameters: {
      'type': 'object',
      'properties': {
        'js': {
          'type': 'string',
          'description': 'The name of the js to execute'
        },
        'data': {
          'type': 'string',
          'description': 'Fill in the specific json parameters according to the skill description you have loaded.'
        }
      },
      'required': ['data']
    }
  );

  /// 获取所有预定义工具列表
  static List<Tool> get all => [
    load_skill,
    run_intent,
    run_js,
  ];

  static String? _cachedSkillPrompt;

  /// 加载 JSON 索引并构建大模型的全局系统提示词
  Future<String> generateSkillPrompt() async {
    if (_cachedSkillPrompt != null) return _cachedSkillPrompt!;
    
    try {
      // 1. 标准方法：通过 rootBundle 读取本地 JSON 资产文件的文本内容
      final String jsonString = await rootBundle.loadString('assets/skills/skills_index.json');

      // 2. 将文本解码为 Dart 的 List 结构
      final List<dynamic> skillsData = json.decode(jsonString);

      // 3. 构建基础的 System Prompt 框架
      StringBuffer promptBuilder = StringBuffer();

      // 4. 遍历 List，将每个技能的 id 和描述拼接进字符串
      for (var skill in skillsData) {
        final String id = skill['id'] ?? '';
        final String description = skill['description'] ?? '';

        if (id.isNotEmpty) {
          promptBuilder.writeln("- `$id`: $description");
        }
      }

      // 5. 返回最终的系统提示词字符串
      _cachedSkillPrompt = promptBuilder.toString();
      return _cachedSkillPrompt!;
    } catch (e) {
      // 容错处理：如果文件丢失，给模型一个基础无技能的兜底提示词
      return "你是一个端侧 AI 助手。当前系统暂无可调用的外部技能。";
    }
  }

  Future<Map<String, dynamic>> executeFunction(String funName, Map<String, dynamic> args) async {
    try {
      switch (funName) {
        case "speak":
          return await Speak(args);

        case "load_skill":
          return await LoadSkill(args);

        case "run_intent":
          return await RunIntent(args);

        case "run_js":
          return await RunJs(args);

        default:
          return {"status": "error", "message": "Unknown tool: $funName"};
      }
    } catch (e) {
      return {
        "status": "error",
        "message": "Execution failed: ${e.toString()}"
      };
    }
  }

  Future<Map<String, dynamic>> LoadSkill(Map<String, dynamic> args) async {
    final skill_name = args['skill_name'] as String?;

    String skill_detail = await loadSkillDocumentFromFolder(skill_name!);
    return {
      "status": "success",
      "message": skill_detail
    };
  }

  Future<String> loadSkillDocumentFromFolder(String skillFolderName) async {
    try {
      // 1. 动态拼接独立文件夹下的 SKILL.md 路径
      final String assetPath = 'assets/skills/$skillFolderName/SKILL.md';

      // 2. 标准方法：读取文本内容
      final String content = await rootBundle.loadString(assetPath);
      return content;
    } catch (e) {
      print('从文件夹加载技能文档失败: $e');
      return '错误：在技能目录 [$skillFolderName] 下未找到 SKILL.md 配置文件。';
    }
  }

  Future<Map<String, dynamic>> RunIntent(Map<String, dynamic> args) async {
    String funName = args['intent'];
    try {
      switch (funName) {
        case "speak":
          return await Speak(args);

        case "addVocabulary":
          return await AddVocabulary(args);

        case "searchWeb":
          return await SearchWeb(args);

        case "getRandomVocab":
          return await getRandomVocab();

        default:
          return {"status": "error", "message": "Unknown tool: $funName"};
      }
    } catch (e) {
      return {
        "status": "error",
        "message": "Execution failed: ${e.toString()}"
      };
    }
  }

  Future<Map<String, dynamic>> Speak(Map<String, dynamic> args) async {
    final text = args['text'] as String?;
    if (text == null || text.isEmpty) {
      return {"status": "error", "message": "Missing 'text' parameter"};
    }
    await EdgeTtsService().speak(text);
    return {"status": "success", "message": "Spoken: $text"};
  }

  Future<Map<String, dynamic>> AddVocabulary(Map<String, dynamic> args) async {
    Map<String, dynamic> p = jsonDecode(args["parameters"]);
    final word = p["vocabulary"];
    if (word == null || word.isEmpty) {
      return {"status": "error", "message": "Missing 'vocabulary' parameter"};
    }

    final dictEntries = await DictionaryService().searchEntries(word);
    if (dictEntries.isEmpty) {
      return {"status": "error", "message": "Word '$word' not found in dictionary"};
    }

    final entry = dictEntries.first;
    final isCollected = await VocabularyService().isCollected(entry.entSeq);

    if (isCollected) {
      return {"status": "success", "message": "'$word' is already in the study list"};
    }

    await VocabularyService().addEntry(VocabularyEntry(
      entSeq: entry.entSeq,
      word: entry.kanji.isNotEmpty ? entry.kanji.first.written : entry.kana.first.written,
      kana: entry.kana.first.written,
      addTime: DateTime.now(),
      reviewTime: DateTime.now(),
    ));

    return {"status": "success", "message": "Successfully added '$word' to study list"};
  }

  Future<Map<String, dynamic>> getRandomVocab() async {
    try {
      final entries = await VocabularyService().getRandomEntries(10);
      if (entries.isEmpty) {
        return {
          "status": "success",
          "message": "The study list is currently empty.",
          "data": []
        };
      }

      List<Map<String, String>> resultData = [];
      for (var entry in entries) {
        // 从字典服务获取详细释义
        final senses = await DictionaryService().getSensesByEntSeq(entry.entSeq);
        // 提取第一个 Sense 的所有 glosses 并合并为字符串
        String meanings = senses.isNotEmpty
            ? senses.first.glosses.join(', ')
            : "No definition found";

        resultData.add({
          "japanese": entry.word,
          "english": meanings
        });
      }

      return {
        "status": "success",
        "message": "Successfully retrieved 10 random words from the study list.",
        "data": resultData
      };
    } catch (e) {
      return {
        "status": "error",
        "message": "Failed to get random vocabulary: ${e.toString()}"
      };
    }
  }

  Future<Map<String, dynamic>> SearchWeb(Map<String, dynamic> args) async {
    Map<String, dynamic> p = jsonDecode(args["parameters"]);
    String keyword = p["keyword"];
    final FunctionResponse response = await Supabase.instance.client.functions.invoke('search-web',
        body: {"keyword": keyword}
    );
    // 2. 检查 HTTP 状态码
    if (response.status == 200) {
      // response.data 会自动被解析为 Map
      final Map<String, dynamic> result = response.data;

      if (result['success'] == true) {
        // 打印一下当前调用的是哪个引擎（Tavily 或 Jina）
        print("搜索成功！当前使用的引擎: ${result['engine']}");
        return result;
      } else {
        print("云端函数业务逻辑失败: ${result['error']}");
        return {"status": "failed", "message": "Search quota exhausted. Currently, the web search function is unavailable."};
      }
    } else {
      print("服务器响应异常，状态码: ${response.status}");
      return {"status": "failed", "message": "Encountered a network issue, currently unable to perform web search."};
    }
  }

  Future<Map<String, dynamic>> RunJs(Map<String, dynamic> args) async {
    final webName = args['js'] as String?;
    dynamic rawData = args['data'];
    String data;
    if (rawData is Map) {
      data = jsonEncode(rawData);
    } else {
      data = rawData as String? ?? "{}";
    }
    
    if (webName == null) {
      return {"status": "error", "message": "Missing 'js' (webName) parameter"};
    }

    return {
      "status": "render_webview",
      "webName": webName,
      "jsonData": data,
      "htmlPath": "assets/skills/$webName/index.html"
    };
  }
}
