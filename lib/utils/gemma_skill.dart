import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';

class GemmaSkill {
  InferenceModelSession? _activeSession;

  InferenceModel? get _currentModel => MascotController().model;

  /// 初始化并加载模型 (现在由 MascotController 统一管理)
  Future<void> initialize({
    File? modelFile,
    bool enableVision = false,
    bool enableAudio = false,
  }) async {
    // 如果 MascotController 还没加载好模型，这里可以尝试确保加载
    if (_currentModel == null) {
      await MascotController().init();
    }
  }

  Future<void> stopGenerate() async {
    if (_activeSession != null) {
      await _activeSession!.stopGeneration();
      await _activeSession?.close();
      _activeSession = null;
    }
  }

  /// 通用流式生成方法
  Stream<String> _generate({
    required String prompt,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    double temperature = 1.0,
    int topK = 64,
    double topP = 0.95,
    bool? enableThinking
  }) async* {
    if (_currentModel == null) {
      yield "错误：模型未初始化";
      return;
    }

    if (imageBytes == null && audioBytes == null) {
      _activeSession = await _currentModel!.openSession(
          temperature: temperature,
          topK: topK,
          topP: topP,
          enableVisionModality: imageBytes != null,
          enableAudioModality: audioBytes != null,
          enableThinking: enableThinking == null ? MascotController().isThinkingMode : enableThinking,
          systemInstruction: "Output strictly in the format specified by the user's prompt words. Prohibit any greetings outside the specified format."
      );
    } else {
      _activeSession = await _currentModel!.createSession(
          temperature: temperature,
          topK: topK,
          topP: topP,
          enableVisionModality: imageBytes != null,
          enableAudioModality: audioBytes != null,
          enableThinking: enableThinking == null ? MascotController().isThinkingMode : enableThinking,
          systemInstruction: "Output strictly in the format specified by the user's prompt words. Prohibit any greetings outside the specified format."
      );
    }

    Message message;
    if (imageBytes != null) {
      message = Message.withImage(text: prompt, imageBytes: imageBytes);
    } else if (audioBytes != null) {
      message = Message.withAudio(text: prompt, audioBytes: audioBytes);
    } else {
      message = Message.text(text: prompt);
    }

    await _activeSession!.addQueryChunk(message);
    final stream = _activeSession!.getResponseAsync();

    try {
      await for (final response in stream) {
        yield response;
      }
    } catch (e) {
      yield "生成出错: $e";
    } finally {
      await _activeSession?.close();
      _activeSession = null;
    }
  }

  /// 强制停止并关闭当前会话
  Future<void> close() async {
    try {
      if (_activeSession != null) {
        await _activeSession!.stopGeneration();
        await _activeSession!.close();
        _activeSession = null;
      }
    } catch (e) {
      debugPrint("GemmaSkill 关闭失败: $e");
    }
  }

  /// 纯语音转文字 (利用多模态音频输入)
  Stream<String> transcribeSpeech({required Uint8List audioBytes}) {
    return _generate(
      prompt: "Transcribe this Japanese audio into text accurately. Output only the transcription, no translation.",
      audioBytes: audioBytes,
    );
  }

  // ================= 观世 (Vision) =================

  /// 文字提取 (OCR)
  Stream<String> extractText({required Uint8List imageBytes}) {
    return _generate(
      prompt: "Extract and list all the Japanese text visible in the picture. Just output the extracted text, without any additional descriptions.",
      imageBytes: imageBytes,
    );
  }

  /// 场景描述
  Stream<String> describeScene({required Uint8List imageBytes}) {
    return _generate(
      prompt: "Describe the scene in this picture in Japanese.",
      imageBytes: imageBytes,
    );
  }

  /// 看图识物
  Stream<String> recognizeObject({required Uint8List imageBytes}) {
    return _generate(
      prompt: "Identify the main object in this picture and directly output the item name in a comma-separated format.Please answer in Japanese.",
      imageBytes: imageBytes,
    );
  }

  /// 看图识物标记
  Stream<String> recognizeMarkObject({required Uint8List imageBytes}) {
    return _generate(
      prompt: """
Please identify the main objects in following picture and mark the center positions of the objects with coordinates. Please use Japanese object name.
format:
[
  {
    "label": "object name",
    "position": [pos_x, pos_y]
  },
  and then other objects
]
""",
      imageBytes: imageBytes,
    );
  }

  /// 文化解析
  Stream<String> cultureResolve({required String res}) {
    return _generate(
      prompt: "Please introduce the related culture of [$res] in Japan. Answer in Japanese.",
    );
  }

  /// 台词翻译
  Stream<String> translateLines({required Uint8List imageBytes, String targetLang = "中文"}) {
    return _generate(
      prompt: "Identify the Japanese lines or dialogues in the pictures and translate them into $targetLang. Please provide the necessary tone analysis in Chinese.",
      imageBytes: imageBytes,
    );
  }

  /// 题目分析
  Stream<String> analyzeProblem({required Uint8List imageBytes, String? additionalContext}) {
    String prompt = """
Recognize the content of Japanese problem in the following image, then provide the problem-solving strategies and steps.
when formatting the answer, first output the answer of problem, then one newline, then output the string '分析: ', then the strategies and steps in Chinese.
""";
    if (additionalContext != null && additionalContext.isNotEmpty) {
      prompt = "$prompt\n\nAddition information of problem：$additionalContext\n\n";
    }
    return _generate(
      prompt: prompt,
      imageBytes: imageBytes,
    );
  }

  // ================= 闻讯 (Audio) =================

  /// 发音分析
  Stream<String> analyzePronunciation({required Uint8List audioBytes, required String example}) {
    return _generate(
      prompt: """
You are an expert Japanese language tutor. Compare the provided speech segment with the reference sentence provided below.

Reference Sentence: "${example}"

Task:
1. Transcribe the user's speech in Japanese.
2. Compare the transcription and the phonetic performance with the Reference Sentence.
3. Analyze pronunciation issues, focusing on:
    - Pitch Accent (High/Low patterns)
    - Rhythm (Long vowels, sokuon/促音, and n/拨音)
    - Specific Phonemes (e.g., 'r' sound, devocalization of vowels)

Formatting:
- Transcription: [Output the transcribed Japanese text]
- Analysis: 
    - Accuracy: [Did the user say the correct words?]
    - Pronunciation: [Specific feedback on accent and rhythm]
- Advice: [How to improve]
Output in Chinese.
""",
      audioBytes: audioBytes,
    );
  }

  /// 语气分析
  Stream<String> analyzeTone({required Uint8List audioBytes, required scenario}) {
    return _generate(
      prompt: """
Transcribe the following speech segment in Japanese, then analyze the tone and emotion.
When formatting the answer, first output the transcription in Japanese, then one newline, then output the string '分析: ', then the analyzation in Chinese.
""",
      audioBytes: audioBytes,
    );
  }

  /// 语音翻译
  Stream<String> translateSpeech(
      {required Uint8List audioBytes,
        String sourceLang = "Japanese",
        String targetLang = "Chinese"}) {
    return _generate(
      prompt: """
Transcribe the following speech segment in ${sourceLang}, then translate it into ${targetLang}.
When formatting the answer, first output the transcription in ${sourceLang}, then one newline, then output the string '${targetLang}: ', then the translation in ${targetLang}.
""",
      audioBytes: audioBytes,
    );
  }

  /// 全双工语音对话
  Stream<String> audioChat({required Uint8List audioBytes}) {
    return _generate(
      prompt: "You are a caring Japanese conversation assistant named Iris. Please listen to the user's voice input (in Japanese), and respond in Japanese, maintaining a natural and smooth conversation. Just output your reply content directly.",
      audioBytes: audioBytes,
    );
  }

  // ================= 基础能力 =================

  /// 语法分析
  Stream<String> analyzeGrammar({required String textContent}) {
    final prompt = """
Role: You are a professional linguist and grammar expert.
Task: Analyze the grammar and structure of the provided japanese dialogue sentences.
Dialogue:
$textContent

Output format (Chinese rely): 
1. The translation to Chinese.
2. Identify key grammar points, sentence structures, and possible errors.
""";
    return _generate(prompt: prompt);
  }

  /// 句子检查
  Stream<String> sentenceCheck({required String textContent}) {
    final prompt = """
Role: You are a professional linguist and grammar expert.
Task: Check the grammar of the provided dialogue sentences.
Dialogue:
$textContent

Output format (Chinese reply): 
1. 正确 or 错误.
2. Please give reasons if the sentence is error.
""";
    return _generate(prompt: prompt);
  }
  /// 日语翻译
  Stream<String> japaneseTranslate({required String content, String targetLang = "Chinese", bool? enableThinking}) {
    return _generate(
      prompt: """
Translate the '$content' into $targetLang.
When formatting the answer, output the the translation only.
""",
      enableThinking: enableThinking == null ? MascotController().isThinkingMode : enableThinking,
    );
  }

  /// 生词解析
  Stream<String> vocabularyAnalyze({required String content}) {
    return _generate(
      prompt: "Please analyze: The Japanese word '$content', including its part of speech, pronunciation, usage and examples.",
    );
  }

  /// 随机句子
  Stream<String> exampleSentence() {
    return _generate(
      prompt: "Give me a concise Japanese example sentence. just reply the sentence. now is ${DateTime.now().millisecondsSinceEpoch}",
      enableThinking: false
    );
  }

  /// 随机句子
  Stream<String> exampleSentenceByWord({required String word}) {
    return _generate(
      prompt: "Generate a random Japanese sentence using '$word'. now is ${DateTime.now().millisecondsSinceEpoch}",
      enableThinking: false
    );
  }

  /// 题目生成方法
  Stream<String> generateProblem({
    required String typeQ,
    required String level,
  }) {
    return _generate(
      prompt: """
You are a professional expert in Japanese education. Please create a Japanese practice question based on the following requirements:
- Question Type：$typeQ
- JLPT level：$level

Output format should remain clear. Please ensure the accuracy and professionalism of the content. And follow the language requirements in the following format.

formatting:
output the string 'Q', then new line
1. Question content and options (if the question need options) in Japanese.
then new line, output string '@Ans', then new line
2. Correct answer
3. Analyze in Chinese
""",
    );
  }

  Stream<String> scenarioAsk() {
    return _generate(
      prompt: """
Generate a random daily scene and assign two roles. One of the roles will make a Japanese question that fits the scene. Now is ${DateTime.now()}.
Output format:
Scene: Scene setting.
Ai: Role of the AI.
You: The role assigned to the user.
Ai's role's question: Question content
""",
    );
  }
  
  Stream<String> dailyTip() {
    DateTime now = DateTime.now();

    int year = now.year;   // 2026
    int month = now.month; // 5
    int day = now.day;     // 24

    // 拼接成字符串 (例如: 2026-5-24)
    String dateStr = "$year-$month-$day";
    return _generate(prompt: "Randomly generate a daily Japanese knowledge point, reply in Chinese, format include the knowledge point and its introduce and history. Today is ${dateStr}");
  }
  
  /// 通用文本对话
  Stream<String> getMessageByText({required String textContent}) {
    return _generate(prompt: textContent);
  }
}
