import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'package:Iris/utils/edge_tts_service.dart';
import 'audio_common.dart';

class PronunciationAnalysisPage extends StatefulWidget {
  const PronunciationAnalysisPage({super.key});

  @override
  State<PronunciationAnalysisPage> createState() => _PronunciationAnalysisPageState();
}

class _PronunciationAnalysisPageState extends AudioBaseState<PronunciationAnalysisPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();
  final EdgeTtsService _ttsService = EdgeTtsService();
  final TextEditingController _textController = TextEditingController();
  bool _isGeneratingExample = false;
  bool _isPlayingTts = false;
  bool _showTtsSettings = false;

  // TTS 参数
  double _ttsRate = 0.0;    // -50% to +100%
  double _ttsVolume = 0.0;  // -50% to +100%
  double _ttsPitch = 0.0;   // -20Hz to +20Hz

  String _formatValue(double value, String suffix) {
    String prefix = value >= 0 ? "+" : "";
    return "$prefix${value.round()}$suffix";
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _gemmaSkill.close();
    _ttsService.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _generateRandomExample() async {
    if (_isGeneratingExample) return;

    setState(() {
      _isGeneratingExample = true;
      _textController.clear();
    });

    try {
      // 获取模型文件
      if (currentModelFile == null) {
        await loadModelFiles();
      }
      
      if (currentModelFile != null) {
        await _gemmaSkill.initialize(modelFile: currentModelFile!);
        final stream = _gemmaSkill.exampleSentence();
        await for (final chunk in stream) {
          setState(() {
            _textController.text += chunk;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择模型')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成例句失败: $e')));
    } finally {
      setState(() => _isGeneratingExample = false);
    }
  }

  Future<void> _playTts() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isPlayingTts) return;

    setState(() => _isPlayingTts = true);
    try {
      String voice = 'zh-CN-XiaoxiaoNeural';
      if (RegExp(r'[ぁ-んァ-ン]').hasMatch(text)) {
        voice = 'ja-JP-NanamiNeural';
      }
      await _ttsService.speak(
        text, 
        voiceName: voice,
        rate: _formatValue(_ttsRate, "%"),
        volume: _formatValue(_ttsVolume, "%"),
        pitch: _formatValue(_ttsPitch, "Hz"),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('语音播放失败: $e')));
    } finally {
      setState(() => _isPlayingTts = false);
    }
  }

  Future<void> _startAnalysis() async {
    if (audioBytes == null || currentModelFile == null || _textController.text.isEmpty) return;

    setState(() {
      audioState = AudioState.processing;
      resultText = "";
    });

    try {
      await _gemmaSkill.initialize(
        modelFile: currentModelFile!,
        enableAudio: true,
      );

      final stream = _gemmaSkill.analyzePronunciation(
        audioBytes: audioBytes!,
        example: _textController.text.trim(),
      );
      
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
        title: const Text('发音分析', style: TextStyle(fontWeight: FontWeight.bold)),
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
              Icon(Icons.edit_note_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('朗读内容', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _isGeneratingExample ? null : _generateRandomExample,
                icon: _isGeneratingExample 
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.casino_outlined, size: 18),
                label: const Text('随机句子'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '输入或粘贴想要练习的内容...',
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              suffixIcon: _textController.text.isNotEmpty 
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_showTtsSettings ? Icons.tune_rounded : Icons.tune_outlined),
                          onPressed: () => setState(() => _showTtsSettings = !_showTtsSettings),
                          color: _showTtsSettings ? colorScheme.primary : Colors.grey,
                          tooltip: "调节语速音调",
                        ),
                        IconButton(
                          icon: Icon(_isPlayingTts ? Icons.volume_up_rounded : Icons.volume_up_outlined),
                          onPressed: _playTts,
                          color: colorScheme.primary,
                          tooltip: "播放示范读音",
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          if (_showTtsSettings && _textController.text.isNotEmpty)
            _buildTtsSettingsPanel(colorScheme),
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
                  child: Icon(Icons.mic_none_rounded, size: 64, color: colorScheme.primary),
                ),
                const SizedBox(height: 24),
                const Text('准备好后点击下方按钮录音', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _textController.text.trim().isEmpty ? null : startRecording,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('开始练习'),
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

  Widget _buildTtsSettingsPanel(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _ttsRate = 0;
                _ttsVolume = 0;
                _ttsPitch = 0;
              });
            },
            child: const Icon(
              Icons.refresh,
              color: Colors.pinkAccent,
              size: 30,
            ),
          ),
          _buildTtsSlider(
            label: "语速",
            value: _ttsRate,
            min: -50,
            max: 100,
            suffix: "%",
            onChanged: (v) => setState(() => _ttsRate = v),
          ),
          _buildTtsSlider(
            label: "音量",
            value: _ttsVolume,
            min: -50,
            max: 50,
            suffix: "%",
            onChanged: (v) => setState(() => _ttsVolume = v),
          ),
          _buildTtsSlider(
            label: "音高",
            value: _ttsPitch,
            min: -100,
            max: 100,
            suffix: "Hz",
            onChanged: (v) => setState(() => _ttsPitch = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTtsSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            _formatValue(value, suffix),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildStreamingView(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 32),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        const Text('Iris 正在分析您的发音...', style: TextStyle(fontWeight: FontWeight.w500)),
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
              child: MarkdownBody(data: resultText.isEmpty ? "正在对比原文进行深度分析..." : resultText),
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
        Icon(Icons.analytics_rounded, size: 64, color: colorScheme.primary),
        const SizedBox(height: 16),
        const Text('发音评估报告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    Icon(Icons.assessment_outlined, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('建议与修正', style: TextStyle(fontWeight: FontWeight.bold)),
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
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('再次练习'),
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
