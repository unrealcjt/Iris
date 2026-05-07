import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../gemma_skill.dart';
import '../scenario_chat_page.dart';
import 'vision_common.dart';

class SceneDescriptionPage extends StatefulWidget {
  const SceneDescriptionPage({super.key});

  @override
  State<SceneDescriptionPage> createState() => _SceneDescriptionPageState();
}

class _SceneDescriptionPageState extends VisionBaseState<SceneDescriptionPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();

  @override
  void dispose() {
    _gemmaSkill.close();
    super.dispose();
  }

  Future<void> _startDescription() async {
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

      final stream = _gemmaSkill.describeScene(imageBytes: imageBytes!);
      await for (final chunk in stream) {
        setState(() {
          if (visionState == VisionState.processing) {
            visionState = VisionState.result;
          }
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

  void _showImportPanel() {
    final scController = TextEditingController(text: resultText);
    final aiCharController = TextEditingController(text: "一位身处此景的当地人");
    final userCharController = TextEditingController(text: "一位对这里感到好奇的游客");
    String aiGender = "女";
    String userGender = "男";
    String selectedLang = "日本語";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("导入并开启场景对话", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: scController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "场景描述 (已预填)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("对话语言", style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: selectedLang,
                      items: ["中文", "English", "日本語"].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                      onChanged: (val) => setModalState(() => selectedLang = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text("AI 角色设定", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aiCharController,
                        decoration: const InputDecoration(hintText: "角色背景"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: aiGender,
                      items: ["男", "女"].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (val) => setModalState(() => aiGender = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text("用户角色设定", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: userCharController,
                        decoration: const InputDecoration(hintText: "角色背景"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: userGender,
                      items: ["男", "女"].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (val) => setModalState(() => userGender = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final preset = ScenarioPreset(
                        name: "来自实景扫描",
                        scenario: scController.text,
                        aiCharacter: aiCharController.text,
                        aiGender: aiGender,
                        userCharacter: userCharController.text,
                        userGender: userGender,
                        language: selectedLang,
                      );
                      Navigator.pop(context); // 关闭面板
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ScenarioChatPage(initialPreset: preset),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("进入对话"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('场景描述', style: TextStyle(fontWeight: FontWeight.bold)),
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
          title: '探索眼前的世界',
          description: '拍摄周围的环境或上传图片\nAI 将为您深度解析场景细节并可开启角色扮演',
          icon: Icons.landscape_rounded,
          colorScheme: colorScheme,
        );
      case VisionState.selected:
        return buildSelectedView(
          colorScheme: colorScheme,
          onConfirm: _startDescription,
        );
      case VisionState.processing:
        return buildProcessingView(
          message: '正在构建场景描述...',
          colorScheme: colorScheme,
        );
      case VisionState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Hero(
            tag: 'selected_image',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                imageFile!,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer.withOpacity(0.4),
                  colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('场景解析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                MarkdownBody(
                  data: resultText,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 16, height: 1.6, color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: reset,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('重拍'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showImportPanel,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('导入场景对话'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
