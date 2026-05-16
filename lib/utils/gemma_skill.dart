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
    double topP = 0.95
  }) async* {
    if (_currentModel == null) {
      yield "错误：模型未初始化";
      return;
    }
    
    _activeSession = await _currentModel!.createSession(
      temperature: temperature,
      topK: topK,
      topP: topP,
      enableVisionModality: imageBytes != null,
      enableAudioModality: audioBytes != null,
      systemInstruction: "严格按照用户提示词给出的格式输出，禁止格式外的问候语"
    );

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

  // ================= 观世 (Vision) =================

  /// 文字提取 (OCR)
  Stream<String> extractText({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请提取并列出图片中可见的所有日语文字内容。只需输出提取的文字，不要有多余的描述。",
      imageBytes: imageBytes,
    );
  }

  /// 场景描述
  Stream<String> describeScene({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请使用日语描述这张图片中的场景，包括环境、人物、动作以及整体氛围。",
      imageBytes: imageBytes,
    );
  }

  /// 看图识物
  Stream<String> recognizeObject({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请识别这张图片中的主要物体，直接按照逗号隔开格式输出物品名字。请用日语回答。",
      imageBytes: imageBytes,
    );
  }

  /// 文化解析
  Stream<String> cultureResolve({required String res}) {
    return _generate(
      prompt: "介绍一下在日本的${res}相关文化。请用日语回答。",
    );
  }

  /// 台词翻译
  Stream<String> translateLines({required Uint8List imageBytes, String targetLang = "中文"}) {
    return _generate(
      prompt: "请识别图片中的台词或对话，并将其翻译成$targetLang。请提供必要的语气分析。",
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
      prompt: "你是一个贴心的日语助手 Iris。请听用户的语音输入（日语），并用简洁的日语进行回应，保持对话自然流畅。直接输出你的回复内容。",
      audioBytes: audioBytes,
    );
  }

  // ================= 基础能力 =================

  /// 语法分析
  Stream<String> analyzeGrammar({required String textContent}) {
    final prompt = """
Role: You are a professional linguist and grammar expert.
Task: Analyze the grammar and structure of the provided dialogue sentences.
Dialogue:
$textContent

Output format (Chinese rely): 
1. The translation to Chinese.
2. Identify key grammar points, sentence structures, and possible errors.
""";
    return _generate(prompt: prompt);
  }

  /// 语法分析
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
  Stream<String> japaneseTranslate({required String content, String targetLang = "中文"}) {
    return _generate(
      prompt: """
Translate the '$content' into $targetLang.
When formatting the answer, output the the translation only.
"""
    );
  }

  /// 生词解析
  Stream<String> vocabularyAnalyze({required String content}) {
    return _generate(
      prompt: "请解析: '$content'这个日语生词，包括词性、读音、用法和例句",
    );
  }

  /// 随机句子
  Stream<String> exampleSentence() {
    return _generate(
      prompt: "Give me a concise Japanese example sentence. just reply the sentence. now is ${DateTime.now().millisecondsSinceEpoch}",
    );
  }

  /// 随机句子
  Stream<String> exampleSentenceByWord({required String word}) {
    return _generate(
      prompt: "使用'${word}'生成一句日语例句. now is ${DateTime.now().millisecondsSinceEpoch}",
    );
  }

  /// 完善后的题目生成方法
  Stream<String> generateProblem({
    required String module,
    required String typeQ,
    required String level,
    int count = 1,
  }) {
    return _generate(
      prompt: """
You are a professional expert in Japanese education. Please create a Japanese practice question based on the following requirements:
- Question Type Section：$module
- Question Type：$typeQ
- Difficulty level：$level

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
随机生成一个日常场景，分配两个角色，其中一个角色发出一句符合场景的日语询问。Now is ${DateTime.now()}。
输出格式:
场景: 场景设定。
Ai: Ai的角色(例如小王)。
你: 给用户分配的角色。
小王询问: 询问内容，使用日语。
""",
    );
  }
  
  /// 通用文本对话
  Stream<String> getMessageByText({required String textContent}) {
    return _generate(prompt: textContent);
  }
}
