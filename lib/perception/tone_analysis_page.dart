import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'audio_common.dart';

class ToneAnalysisPage extends StatefulWidget {
  const ToneAnalysisPage({super.key});

  @override
  State<ToneAnalysisPage> createState() => _ToneAnalysisPageState();
}

class _ToneAnalysisPageState extends AudioBaseState<ToneAnalysisPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();
  final TextEditingController _scenarioController = TextEditingController();
  bool _isGeneratingScenario = false;

  @override
  void dispose() {
    _gemmaSkill.close();
    _scenarioController.dispose();
    super.dispose();
  }

  Future<void> _generateRandomScenario() async {
    if (_isGeneratingScenario) return;

    setState(() {
      _isGeneratingScenario = true;
      _scenarioController.clear();
    });

    try {
      await _gemmaSkill.initialize();
      final stream = _gemmaSkill.scenarioAsk();
      await for (final chunk in stream) {
        if (chunk.endsWith('<channel|>')) {
          continue;
        }
        else {
          setState(() {
            _scenarioController.text += chunk;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成场景失败: $e')));
    } finally {
      setState(() => _isGeneratingScenario = false);
    }
  }

  Future<void> _startAnalysis() async {
    if (audioBytes == null || _scenarioController.text.isEmpty) return;

    setState(() {
      audioState = AudioState.processing;
      resultText = "";
    });

    try {
      await _gemmaSkill.initialize(
        enableAudio: true,
      );

      final stream = _gemmaSkill.analyzeTone(
        audioBytes: audioBytes!,
        scenario: _scenarioController.text.trim(),
      );
      
      await for (final chunk in stream) {
        if (chunk.endsWith('<channel|>')) {
          continue;
        }
        else {
          setState(() {
            resultText += chunk;
          });
        }
      }
      setState(() {
        audioState = AudioState.result;
      });
    } catch (e) {
      setState(() {
        resultText = "分析出错: $e";
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
        title: const Text('语气分析', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
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
        return _buildInputView(colorScheme);
      case AudioState.recording:
        return buildRecordingView(colorScheme: colorScheme);
      case AudioState.selected:
        return buildSelectedView(
          colorScheme: colorScheme,
          onConfirm: _startAnalysis,
        );
      case AudioState.processing:
        return _buildStreamingView(colorScheme);
      case AudioState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildInputView(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.theater_comedy_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('场景设定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _isGeneratingScenario ? null : _generateRandomScenario,
                icon: _isGeneratingScenario 
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('随机生成'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _scenarioController,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: '描述一个场景或点击随机生成...',
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.record_voice_over_rounded, size: 64, color: colorScheme.primary),
                ),
                const SizedBox(height: 24),
                const Text('根据场景录制你的回答', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _scenarioController.text.trim().isEmpty ? null : startRecording,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('开始录音'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingView(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        const Text('Iris 正在分析您的语气...', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('当前场景：', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  MarkdownBody(data: _scenarioController.text),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  MarkdownBody(data: resultText.isEmpty ? "正在分析中..." : resultText),
                ],
              ),
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
        Icon(Icons.sentiment_very_satisfied_rounded, size: 64, color: colorScheme.primary),
        const SizedBox(height: 16),
        const Text('语气评估报告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    Icon(Icons.psychology_alt_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('语气评估报告', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () {
                        final fullContent = "场景：\n${_scenarioController.text}\n\n评估结果：\n$resultText";
                        Clipboard.setData(ClipboardData(text: fullContent));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制完整报告')));
                      },
                    )
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('设定场景', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          MarkdownBody(data: _scenarioController.text),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(),
                          ),
                          const Text('分析结果', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          MarkdownBody(data: resultText),
                        ],
                      ),
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
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('尝试新场景'),
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
