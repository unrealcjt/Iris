import 'package:flutter/material.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';
import 'package:Iris/utils/wa_colors.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:async';

class TrialQuestion {
  String question;
  String answer;
  bool showAnswer;
  bool isParsingAnswer;

  TrialQuestion({
    required this.question,
    required this.answer,
    this.showAnswer = false,
    this.isParsingAnswer = true,
  });
}

class TrialPage extends StatefulWidget {
  const TrialPage({super.key});

  @override
  State<TrialPage> createState() => _TrialPageState();
}

class _TrialPageState extends State<TrialPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();

  String _selectedModule = '语言知识';
  String _selectedType = '单词';
  String _selectedLevel = 'N3';
  int _questionCount = 1;

  final List<TrialQuestion> _questions = [];
  bool _isGenerating = false;
  String _currentGeneratingText = "";
  final ScrollController _scrollController = ScrollController();

  final List<String> _modules = ['语言知识', '阅读', '语法', '综合'];
  final List<String> _types = ['单词', '选择题', '填空题', '判断题', '翻译题'];
  final List<String> _levels = ['N1', 'N2', 'N3', 'N4', 'N5'];

  @override
  void dispose() {
    _gemmaSkill.stopGenerate();
    super.dispose();
  }

  Future<void> _startGeneration() async {
    if (MascotController().model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模型未加载，请在设置中选择模型')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      for (int i = 0; i < _questionCount; i++) {
        if (!mounted || !_isGenerating) break;

        _currentGeneratingText = "";
        final stream = _gemmaSkill.generateProblem(
          module: _selectedModule,
          typeQ: _selectedType,
          level: _selectedLevel,
          count: 1,
        );

        await for (final chunk in stream) {
          if (!mounted) break;
          setState(() {
            _currentGeneratingText += chunk;
          });
          _scrollToBottom();
        }

        if (_currentGeneratingText.isNotEmpty) {
          _parseAndAddQuestion(_currentGeneratingText);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("生成出错: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentGeneratingText = "";
        });
      }
    }
  }

  void _parseAndAddQuestion(String rawText) {
    // 根据 @Ans 进行切割
    final parts = rawText.split(RegExp(r'@Ans\n|@Ans'));
    String qText = "";
    String aText = "未识别到解析内容";

    if (parts.length >= 2) {
      qText = parts[0].replaceAll(RegExp(r'^[Qq]\n|[Qq]:|#'), '').trim();
      aText = parts.sublist(1).join('\n').trim();
    } else {
      qText = rawText.replaceAll(RegExp(r'^[Qq]\n'), '').trim();
    }

    if (qText.isNotEmpty) {
      setState(() {
        _questions.add(TrialQuestion(
          question: qText,
          answer: aText,
          isParsingAnswer: false,
        ));
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleAllAnswers(bool show) {
    setState(() {
      for (var q in _questions) {
        q.showAnswer = show;
      }
    });
  }

  void _clearAll() {
    setState(() {
      _questions.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日语能力试炼', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (_questions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空所有',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildConfigCard(colorScheme),
          if (_questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _toggleAllAnswers(true),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('显示所有答案'),
                  ),
                  TextButton.icon(
                    onPressed: () => _toggleAllAnswers(false),
                    icon: const Icon(Icons.visibility_off, size: 18),
                    label: const Text('隐藏所有答案'),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildQuestionList(colorScheme)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGenerating ? () => setState(() {_isGenerating = false; _gemmaSkill.stopGenerate();}) : _startGeneration,
        icon: Icon(_isGenerating ? Icons.stop_circle_outlined : Icons.bolt_rounded),
        label: Text(_isGenerating ? '停止生成' : '开始试炼'),
        backgroundColor: _isGenerating ? Colors.redAccent : colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildConfigCard(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildDropdown('板块', _selectedModule, _modules, (v) => setState(() => _selectedModule = v!))),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdown('类型', _selectedType, _types, (v) => setState(() => _selectedType = v!))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildDropdown('等级', _selectedLevel, _levels, (v) => setState(() => _selectedLevel = v!))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('题目数量: $_questionCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Slider(
                      value: _questionCount.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: _questionCount.toString(),
                      onChanged: _isGenerating ? null : (v) => setState(() => _questionCount = v.toInt()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: _isGenerating ? null : onChanged,
        ),
      ],
    );
  }

  Widget _buildQuestionList(ColorScheme colorScheme) {
    if (_questions.isEmpty && !_isGenerating) {
      return const Center(child: Text('准备好了吗？点击下方按钮开始试炼', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _questions.length + (_isGenerating ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _questions.length) {
          return _buildGeneratingIndicator(colorScheme);
        }
        return _buildQuestionCard(_questions[index], index);
      },
    );
  }

  Widget _buildQuestionCard(TrialQuestion q, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: WaColors.akaRed.withOpacity(0.1),
              child: Text('${index + 1}', style: const TextStyle(color: WaColors.akaRed, fontWeight: FontWeight.bold)),
            ),
            title: const Text('问题', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
              onPressed: () => setState(() => _questions.removeAt(index)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: MarkdownBody(
              data: q.question,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => q.showAnswer = !q.showAnswer),
                  icon: Icon(q.showAnswer ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  label: Text(q.showAnswer ? '隐藏答案' : '显示答案'),
                  style: TextButton.styleFrom(foregroundColor: WaColors.akaRed),
                ),
              ],
            ),
          ),
          if (q.showAnswer)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WaColors.akaRed.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('答案与解析:', style: TextStyle(fontWeight: FontWeight.bold, color: WaColors.akaRed, fontSize: 14)),
                  const SizedBox(height: 8),
                  MarkdownBody(
                    data: q.answer,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeneratingIndicator(ColorScheme colorScheme) {
    bool hasAns = _currentGeneratingText.contains('@Ans');
    String displayQuestion = _currentGeneratingText;
    bool isGeneratingAns = false;

    if (hasAns) {
      final parts = _currentGeneratingText.split(RegExp(r'@Ans\n|@Ans'));
      displayQuestion = parts[0].replaceAll(RegExp(r'^[Qq]\n|[Qq]:|#'), '').trim();
      isGeneratingAns = true;
    } else {
      displayQuestion = _currentGeneratingText.replaceAll(RegExp(r'^[Qq]\n|[Qq]:|#'), '').trim();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(
                isGeneratingAns ? '题目生成完成，正在解析答案...' : '正在努力生成第 ${_questions.length + 1} 题...',
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          if (displayQuestion.isNotEmpty) ...[
            const SizedBox(height: 12),
            MarkdownBody(
              data: displayQuestion,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
              ),
            ),
          ],
          if (isGeneratingAns)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined, size: 16, color: WaColors.akaRed.withOpacity(0.5)),
                  const SizedBox(width: 8),
                  const Text('AI 正在思考解析内容...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
        ],
      ),
    );
  }
}
