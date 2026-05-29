import 'package:Iris/utils/edge_tts_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jm/dictionary_service.dart';
import '../practice/vocabulary_model.dart';
import '../practice/vocabulary_service.dart';

/// Iris 助手可用的函数工具定义类
class IrisTools {
  /// 语音播报工具
  static const Tool speak = Tool(
    name: 'speak',
    description: 'Text to speech then play.',
    parameters: {
      'type': 'object',
      'properties': {
        'text': {
          'type': 'string',
          'description': 'Text that needs to be converted to audio playback.',
        },
      },
      'required': ['text'],
    },
  );

  static const Tool addVocabulary = Tool(
    name: 'addVocabulary',
    description: 'Add a Japanese vocabulary word to the user\'s study list.',
    parameters: {
      'type': 'object',
      'properties': {
        'vocabulary': {
          'type': 'string',
          'description': 'The vocabulary word (kanji or kana) to be added.',
        },
      },
      'required': ['vocabulary'],
    },
  );

  static const searchWeb = Tool(
      name: "searchWeb",
      description: "Search information from web internet",
      parameters: {
        'type': 'object',
        'properties': {
          'keyword': {
            'type': 'string',
            'description': 'The keywords used in the search'
          },
        },
        'required': ['keyword'],
      }
  );

  /// 获取所有预定义工具列表
  static List<Tool> get all => [
    speak,
    addVocabulary,
    searchWeb
  ];

  Future<Map<String, dynamic>> executeFunction(String funName, Map<String, dynamic> args) async {
    try {
      switch (funName) {
        case "speak":
          return await Speak(args);

        case "addVocabulary":
          return await AddVocabulary(args);

        case "searchWeb":
          return await SearchWeb(args);

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
    final word = args['vocabulary'] as String?;
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

  Future<Map<String, dynamic>> SearchWeb(Map<String, dynamic> args) async {
    final FunctionResponse response = await Supabase.instance.client.functions.invoke('search-web',
        body: {"keyword": args["keyword"] as String}
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
}
