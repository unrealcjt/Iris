import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../gemma_skill.dart';
import 'vision_common.dart';

class TranslateLinesPage extends StatefulWidget {
  const TranslateLinesPage({super.key});

  @override
  State<TranslateLinesPage> createState() => _TranslateLinesPageState();
}

class _TranslateLinesPageState extends VisionBaseState<TranslateLinesPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();
  String _targetLang = "中文";

  @override
  void dispose() {
    _gemmaSkill.close();
    super.dispose();
  }

  Future<void> _startTranslation() async {
    if (imageBytes == null || currentModelFile == null) return;

    setState(() {
      visionState = VisionState.processing;
      resultText = "";
    });

    try {
      await _gemmaSkill.initialize(
        modelFile: currentModelFile!,
        enableVision: true,
      );

      final stream = _gemmaSkill.translateLines(
        imageBytes: imageBytes!,
        targetLang: _targetLang,
      );
      
      await for (final chunk in stream) {
        if (mounted) {
          setState(() {
            if (visionState == VisionState.processing) {
              visionState = VisionState.result;
            }
            resultText += chunk;
          });
        }
      }
      
      setState(() {
        visionState = VisionState.result;
      });
    } catch (e) {
      setState(() {
        resultText = "翻译出错: $e";
        visionState = VisionState.result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('台词翻译', style: TextStyle(fontWeight: FontWeight.bold)),
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
    switch (visionState) {
      case VisionState.initial:
        return buildInitialView(
          title: '对话与台词翻译',
          description: '拍摄漫画、电影剧照或文档\nAI 将自动识别台词并进行精准翻译与语气分析',
          icon: Icons.translate_rounded,
          colorScheme: colorScheme,
        );
      case VisionState.selected:
        return _buildSelectedWithLangView(colorScheme);
      case VisionState.processing:
        return buildProcessingView(
          message: '正在识别并翻译...',
          colorScheme: colorScheme,
        );
      case VisionState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildSelectedWithLangView(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.file(imageFile!, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("目标语言", style: TextStyle(fontWeight: FontWeight.bold)),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: "中文", label: Text("中文")),
                      ButtonSegment(value: "English", label: Text("EN")),
                      ButtonSegment(value: "日本語", label: Text("日語")),
                    ],
                    selected: {_targetLang},
                    onSelectionChanged: (val) => setState(() => _targetLang = val.first),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  buildRoundButton(
                    icon: Icons.close_rounded,
                    color: Colors.redAccent,
                    onTap: reset,
                  ),
                  buildRoundButton(
                    icon: Icons.crop_rounded,
                    color: colorScheme.secondary,
                    onTap: cropImage,
                  ),
                  buildRoundButton(
                    icon: Icons.check_rounded,
                    color: Colors.greenAccent.shade700,
                    onTap: _startTranslation,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(imageFile!, fit: BoxFit.contain, width: double.infinity),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.g_translate_rounded, color: colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text('翻译结果 ($_targetLang)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () => Clipboard.setData(ClipboardData(text: resultText)),
                          ),
                        ],
                      ),
                      const Divider(),
                      MarkdownBody(data: resultText),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: reset,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('换一张'),
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
