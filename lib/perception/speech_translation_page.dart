import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'audio_common.dart';

class SpeechTranslationPage extends StatefulWidget {
  const SpeechTranslationPage({super.key});

  @override
  State<SpeechTranslationPage> createState() => _SpeechTranslationPageState();
}

class _SpeechTranslationPageState extends AudioBaseState<SpeechTranslationPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();

  @override
  void dispose() {
    _gemmaSkill.close();
    super.dispose();
  }

  Future<void> _startTranslation() async {
    if (audioBytes == null || currentModelFile == null) return;

    setState(() {
      audioState = AudioState.processing;
      resultText = "";
    });

    try {
      await _gemmaSkill.initialize(
        modelFile: currentModelFile!,
        enableAudio: true,
      );

      final stream = _gemmaSkill.translateSpeech(audioBytes: audioBytes!);
      await for (final chunk in stream) {
        setState(() {
          resultText += chunk;
        });
      }
      setState(() {
        audioState = AudioState.result;
      });
    } catch (e) {
      setState(() {
        resultText = "识别出错: $e";
        audioState = AudioState.result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('语音翻译', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: showModelPicker,
          )
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildBody(colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    switch (audioState) {
      case AudioState.initial:
        return buildInitialView(
          title: '准备翻译语音',
          description: '点击下方按钮录制一段语音\nAI 将为您自动识别并翻译内容',
          icon: Icons.g_translate_rounded,
          colorScheme: colorScheme,
        );
      case AudioState.recording:
        return buildRecordingView(colorScheme: colorScheme);
      case AudioState.selected:
        return buildSelectedView(
          colorScheme: colorScheme,
          onConfirm: _startTranslation,
        );
      case AudioState.processing:
        return _buildStreamingView(colorScheme);
      case AudioState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildStreamingView(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 32),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        const Text('正在翻译语音...', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 24),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.1)),
            ),
            child: SingleChildScrollView(
              child: MarkdownBody(data: resultText.isEmpty ? "正在处理音频，请稍候..." : resultText),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(Icons.check_circle_rounded, size: 64, color: Colors.greenAccent.shade700),
        const SizedBox(height: 16),
        const Text('翻译完成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('翻译内容', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: resultText));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                      },
                    )
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      child: MarkdownBody(data: resultText),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: reset,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('重新翻译'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
