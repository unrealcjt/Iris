import 'package:Iris/utils/edge_tts_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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

  /// 获取所有预定义工具列表
  static List<Tool> get all => [
    speak,
    addVocabulary,
  ];

  Future<Map<String, dynamic>> executeFunction(String funName, Map<String, dynamic> args) async {
    try {
      switch (funName) {
        case "speak":
          final text = args['text'] as String?;
          if (text == null || text.isEmpty) {
            return {"status": "error", "message": "Missing 'text' parameter"};
          }
          await EdgeTtsService().speak(text);
          return {"status": "success", "message": "Spoken: $text"};

        case "addVocabulary":
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
}
