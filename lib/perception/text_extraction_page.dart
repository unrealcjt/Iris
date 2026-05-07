import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../gemma_skill.dart';
import 'vision_common.dart';

class TextExtractionPage extends StatefulWidget {
  const TextExtractionPage({super.key});

  @override
  State<TextExtractionPage> createState() => _TextExtractionPageState();
}

class _TextExtractionPageState extends VisionBaseState<TextExtractionPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();

  @override
  void dispose() {
    _gemmaSkill.close();
    super.dispose();
  }

  Future<void> _startExtraction() async {
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

      final stream = _gemmaSkill.extractText(imageBytes: imageBytes!);
      await for (final chunk in stream) {
        setState(() {
          resultText += chunk;
        });
      }
      setState(() {
        visionState = VisionState.result;
      });
    } catch (e) {
      setState(() {
        resultText = "识别出错: $e";
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
        title: const Text('文字提取', style: TextStyle(fontWeight: FontWeight.bold)),
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
          title: '准备提取文字',
          description: '点击下方按钮拍照或从相册选择图片\nAI 将为您自动识别其中的文本内容',
          icon: Icons.text_fields_rounded,
          colorScheme: colorScheme,
        );
      case VisionState.selected:
        return buildSelectedView(
          colorScheme: colorScheme,
          onConfirm: _startExtraction,
        );
      case VisionState.processing:
        return buildProcessingView(
          message: '正在解析图片中的文字...',
          colorScheme: colorScheme,
        );
      case VisionState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          onTap: showFullScreenImage,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            constraints: const BoxConstraints(maxHeight: 300),
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(imageFile!, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('识别结果', style: TextStyle(fontWeight: FontWeight.bold)),
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
              label: const Text('再拍一张'),
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
