import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaSkill {
  InferenceModel? _currentModel;
  InferenceModelSession? _activeSession;

  /// 初始化并加载模型
  Future<void> initialize({
    required File modelFile,
    bool enableVision = false,
    bool enableAudio = false,
  }) async {
    // 关闭可能存在的旧模型/会话
    await close();

    // 安装或准备模型
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromFile(modelFile.path)
        .install();

    // 根据模式获取模型
    _currentModel = await FlutterGemma.getActiveModel(
      maxTokens: 2048,
      preferredBackend: PreferredBackend.cpu,
      supportAudio: enableAudio,
      supportImage: enableVision,
    );
  }

  /// 通用流式生成方法
  Stream<String> _generate({
    required String prompt,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    double temperature = 0.8,
    int topK = 40,
  }) async* {
    if (_currentModel == null) {
      yield "错误：模型未初始化";
      return;
    }
    
    _activeSession = await _currentModel!.createSession(
      temperature: temperature,
      topK: topK,
      enableVisionModality: imageBytes != null,
      enableAudioModality: audioBytes != null,
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

  /// 强制停止并关闭所有会话，释放 Native 资源
  Future<void> close() async {
    try {
      if (_activeSession != null) {
        await _activeSession!.stopGeneration();
        await _activeSession!.close();
        _activeSession = null;
      }
      if (_currentModel != null) {
        await _currentModel!.close();
        _currentModel = null;
      }
    } catch (e) {
      debugPrint("GemmaSkill 关闭失败: $e");
    }
  }

  // ================= 观世 (Vision) =================

  /// 文字提取 (OCR)
  Stream<String> extractText({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请提取并列出图片中可见的所有文字内容。只需输出提取的文字，不要有多余的描述。",
      imageBytes: imageBytes,
    );
  }

  /// 场景描述
  Stream<String> describeScene({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请详细描述这张图片中的场景，包括环境、人物、动作以及整体氛围。请用中文回答。",
      imageBytes: imageBytes,
    );
  }

  /// 看图识物
  Stream<String> recognizeObject({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请识别这张图片中的主要物体，说明它们的品类、特征以及可能的用途。请用中文回答。",
      imageBytes: imageBytes,
    );
  }

  /// 台词翻译
  Stream<String> translateLines({required Uint8List imageBytes, String targetLang = "中文"}) {
    return _generate(
      prompt: "请识别图片中的台词或对话，并将其翻译成$targetLang。请保留原有的语气，并提供必要的背景解释。",
      imageBytes: imageBytes,
    );
  }

  /// 题目分析
  Stream<String> analyzeProblem({required Uint8List imageBytes}) {
    return _generate(
      prompt: "请分析图片中的题目。首先识别题目内容，然后提供详细的解题思路和步骤。请用中文回答。",
      imageBytes: imageBytes,
    );
  }

  // ================= 闻讯 (Audio) =================

  /// 发音分析
  Stream<String> analyzePronunciation({required Uint8List audioBytes}) {
    return _generate(
      prompt: "请分析这段音频中的发音。识别其中的发音错误、重音偏移或连读问题，并给出改进建议。请用中文回答。",
      audioBytes: audioBytes,
    );
  }

  /// 语气分析
  Stream<String> analyzeTone({required Uint8List audioBytes}) {
    return _generate(
      prompt: "请分析这段语音的语气和情感状态。判断说话者的情绪（如焦虑、开心、严肃等）以及语气的强弱变化。请用中文回答。",
      audioBytes: audioBytes,
    );
  }

  /// 语音翻译
  Stream<String> translateSpeech({required Uint8List audioBytes, String targetLang = "中文"}) {
    return _generate(
      prompt: "请将这段语音的内容翻译成$targetLang。只需输出翻译后的文本。",
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

Constraint: 
1. Provide a clear, structured analysis.
2. Identify key grammar points, sentence structures, and possible errors.
3. Use Chinese to reply.
""";
    return _generate(prompt: prompt);
  }
  
  /// 通用文本对话
  Stream<String> getMessageByText({required String textContent}) {
    return _generate(prompt: textContent);
  }
}
