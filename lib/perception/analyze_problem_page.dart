import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../gemma_skill.dart';
import 'vision_common.dart';

class AnalyzeProblemPage extends StatefulWidget {
  const AnalyzeProblemPage({super.key});

  @override
  State<AnalyzeProblemPage> createState() => _AnalyzeProblemPageState();
}

class _AnalyzeProblemPageState extends VisionBaseState<AnalyzeProblemPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();
  final TextEditingController _contextController = TextEditingController();

  @override
  void dispose() {
    _gemmaSkill.close();
    _contextController.dispose();
    super.dispose();
  }

  @override
  void reset() {
    super.reset();
    _contextController.clear();
  }

  Future<void> _startAnalysis() async {
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

      final stream = _gemmaSkill.analyzeProblem(
        imageBytes: imageBytes!,
        additionalContext: _contextController.text.trim(),
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
        resultText = "分析出错: $e";
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
        title: const Text('题目分析', style: TextStyle(fontWeight: FontWeight.bold)),
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
          title: '智能解题助手',
          description: '拍摄作业、卷面或书籍中的题目\nAI 将为您提供识别内容、解题思路与详细步骤',
          icon: Icons.menu_book_rounded,
          colorScheme: colorScheme,
        );
      case VisionState.selected:
        return _buildCustomSelectedView(colorScheme);
      case VisionState.processing:
        return buildProcessingView(
          message: '正在思考解题思路...',
          colorScheme: colorScheme,
        );
      case VisionState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildCustomSelectedView(ColorScheme colorScheme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(imageFile!, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: TextField(
              controller: _contextController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "补充说明 (可选)",
                hintText: "如果图片模糊或题目不完整，请在此补充...",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
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
                  onTap: _startAnalysis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(imageFile!, fit: BoxFit.contain, width: double.infinity),
                ),
                if (_contextController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      "补充说明: ${_contextController.text}",
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            Icon(Icons.edit_note_rounded, size: 18, color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              "分析报告",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(24),
                        child: MarkdownBody(
                          data: resultText,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 16, height: 1.7, color: Colors.black87),
                            h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                            h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: reset,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('重拍题目'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
