import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';
import 'package:Iris/utils/wa_colors.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:async';

class JLPTPoint {
  final String title;
  final String format;
  final List<String> supportedLevels;

  JLPTPoint({
    required this.title,
    required this.format,
    required this.supportedLevels,
  });
}

class JLPTCategory {
  final String title;
  final List<JLPTPoint> points;

  JLPTCategory({
    required this.title,
    required this.points,
  });
}

final List<JLPTCategory> jlptData = [
  JLPTCategory(
    title: '言語知識（文字・語彙）',
    points: [
      JLPTPoint(title: '漢字読音', format: '为划线的汉字选择正确的假名读音', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '漢字书写', format: '根据假名选择正确的汉字写法', supportedLevels: ['N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '語彙構成', format: '考察前缀、后缀及复合词 (如: ~性、~化)', supportedLevels: ['N2']),
      JLPTPoint(title: '上下文含义', format: '根据句意选择最合适的词汇 (考词义理解)', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '近义词替换', format: '选择与划线词语意思最接近的选项', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '词语用法', format: '选择给定词语使用最正确的句子 (考词法深度)', supportedLevels: ['N1', 'N2', 'N3']),
    ],
  ),
  JLPTCategory(
    title: '言語知識（文法）',
    points: [
      JLPTPoint(title: '语法选择', format: '考察接续、助词用法及固定语法条目', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '句子排序', format: '将4个选项排序，选出放在“★”位置的选项', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '文章语法', format: '完形填空：在短文中选择符合逻辑的语法或接续词', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
    ],
  ),
  JLPTCategory(
    title: '阅读理解',
    points: [
      JLPTPoint(title: '短文理解', format: '阅读约150-200字短文，回答细节问题', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
      JLPTPoint(title: '中文理解', format: '阅读约450-500字文章，考察逻辑与因果', supportedLevels: ['N1', 'N2', 'N3', 'N4']),
      JLPTPoint(title: '长文理解', format: '约1000字，考察对文章整体结构和作者意图的理解', supportedLevels: ['N1', 'N2', 'N3']),
      JLPTPoint(title: '比较阅读', format: '对比两篇文章，找出作者观点异同', supportedLevels: ['N1', 'N2']),
      JLPTPoint(title: '信息检索', format: '从广告、传单或公告中找出特定信息 (如时间、价格)', supportedLevels: ['N1', 'N2', 'N3', 'N4', 'N5']),
    ],
  ),
];

class TrialPage extends StatefulWidget {
  const TrialPage({super.key});

  @override
  State<TrialPage> createState() => _TrialPageState();
}

class _TrialPageState extends State<TrialPage> {
  String _selectedLevel = 'N1';
  JLPTPoint? _selectedPoint;
  
  InferenceChat? _chat;
  bool _isGenerating = false;
  String _streamingText = "";
  final List<Message> _displayMessages = [];
  
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 隐藏 Iris 悬浮球 - 使用延迟确保在路由切换完成后执行
    Future.microtask(() {
      MascotController().setVisible(false);
    });
    _selectedPoint = jlptData[0].points[0];
    _initChat();
  }

  @override
  void dispose() {
    _chat?.close();
    // 恢复 Iris 悬浮球
    MascotController().setVisible(true);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    final model = MascotController().model;
    if (model == null) return;
    
    try {
      _chat = await model.createChat(
        modelType: ModelType.gemma4,
        temperature: 1.0,
        topP: 0.95,
        topK: 64,
        systemInstruction: """
You are a professional JLPT (Japanese Language Proficiency Test) question creator. Please randomly generate high-quality single-choice practice questions based on the user's provided level and question format. Maintain professionalism and help assess the user's Japanese proficiency.
When asked to create questions, output the question content in neat line breaks, but do not provide the answer. Wait for the user to answer and then let me check their response.
When the user provides an answer for me to check, verify if the answer is correct and provide an explanation in Chinese to the user.
"""
      );
    } catch (e) {
      debugPrint("Init chat error: $e");
    }
  }

  Future<void> _generateQuestion() async {
    if (_selectedPoint == null || _isGenerating) return;
    
    if (_chat == null) {
      await _initChat();
      if (_chat == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模型未就绪')));
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _streamingText = "";
      // 添加一个临时的思考状态消息
      _displayMessages.add(const Message(text: "...", isUser: false, type: MessageType.thinking));
    });

    String? categoryTitle;
    for (var cat in jlptData) {
      if (cat.points.contains(_selectedPoint)) {
        categoryTitle = cat.title;
        break;
      }
    }

    final prompt = "Generate a Japanese question with the following characteristics: the focus is on ${categoryTitle ?? ''} - ${_selectedPoint!.title}, the difficulty level is $_selectedLevel, and the question format is ${_selectedPoint!.format}.";
    
    try {
      await _chat!.addQuery(Message.text(text: prompt, isUser: true));
      
      final stream = _chat!.generateChatResponseAsync();
      bool firstToken = true;
      await for (final response in stream) {
        if (!mounted) break;
        if (response is TextResponse) {
          if (firstToken) {
            setState(() {
              // 移除思考状态消息，开始真实流式展示
              _displayMessages.removeLast();
              firstToken = false;
            });
          }
          setState(() {
            _streamingText += response.token;
          });
          _scrollToBottom();
        }
      }

      if (_streamingText.isNotEmpty) {
        setState(() {
          _displayMessages.add(Message.text(text: _streamingText, isUser: false));
          _streamingText = "";
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _handleSend(String text) async {
    if (text.trim().isEmpty || _isGenerating) return;

    final userMsg = text.trim();
    _inputController.clear();

    setState(() {
      _displayMessages.add(Message.text(text: userMsg, isUser: true));
      _isGenerating = true;
      _streamingText = "";
      // 添加思考状态
      _displayMessages.add(const Message(text: "...", isUser: false, type: MessageType.thinking));
    });
    _scrollToBottom();

    try {
      if (_chat == null) await _initChat();
      
      final wrappedPrompt = "$userMsg\n检查我的答案。";
      await _chat!.addQuery(Message.text(text: wrappedPrompt, isUser: true));

      final stream = _chat!.generateChatResponseAsync();
      bool firstToken = true;
      await for (final response in stream) {
        if (!mounted) break;
        if (response is TextResponse) {
          if (firstToken) {
            setState(() {
              _displayMessages.removeLast();
              firstToken = false;
            });
          }
          setState(() {
            _streamingText += response.token;
          });
          _scrollToBottom();
        }
      }

      if (_streamingText.isNotEmpty) {
        setState(() {
          _displayMessages.add(Message.text(text: _streamingText, isUser: false));
          _streamingText = "";
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: WaColors.washiPaper,
      appBar: AppBar(
        title: const Text('JLPT 试炼场', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: WaColors.sumiBlack,
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('清空对话'),
                  content: const Text('确定要清空当前的练习记录吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消', style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确定', style: TextStyle(color: WaColors.akaRed, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                setState(() {
                  _displayMessages.clear();
                  _chat?.clearHistory();
                });
              }
            },
            tooltip: '清空聊天',
          ),
        ],
      ),
      drawer: isSmallScreen ? Drawer(width: 320, child: _buildSidePanel()) : null,
      body: Row(
        children: [
          if (!isSmallScreen) 
            Container(
              width: 320,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(153),
                border: Border(right: BorderSide(color: Colors.grey.withAlpha(50))),
              ),
              child: _buildSidePanel(),
            ),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildChatView()),
                _buildInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel() {
    return Container(
      color: Colors.white.withAlpha(76),
      child: Column(
        children: [
          _buildLevelSelector(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildPointFolderView()),
        ],
      ),
    );
  }

  Widget _buildLevelSelector() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: WaColors.akaRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text('JLPT 等级', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: WaColors.sumiBlack)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['N1', 'N2', 'N3', 'N4', 'N5'].map((level) {
                final isSelected = _selectedLevel == level;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLevel = level;
                        if (_selectedPoint != null && !_selectedPoint!.supportedLevels.contains(level)) {
                          _selectedPoint = null;
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isSelected ? [
                          BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, 2))
                        ] : null,
                      ),
                      child: Center(
                        child: Text(
                          level,
                          style: TextStyle(
                            color: isSelected ? WaColors.akaRed : Colors.grey.shade600,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointFolderView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: jlptData.length,
      itemBuilder: (context, index) {
        final category = jlptData[index];
        final filteredPoints = category.points.where((p) => p.supportedLevels.contains(_selectedLevel)).toList();
        
        if (filteredPoints.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(204),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 5, offset: const Offset(0, 2))],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.auto_stories_outlined, color: WaColors.kokeGreen, size: 20),
              title: Text(category.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: WaColors.sumiBlack)),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: filteredPoints.map((point) {
                final isSelected = _selectedPoint == point;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2),
                  child: ListTile(
                    contentPadding: const EdgeInsets.only(left: 40, right: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    title: Text(point.title, style: TextStyle(fontSize: 13, color: isSelected ? WaColors.akaRed : Colors.black87, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                    trailing: isSelected ? const Icon(Icons.play_circle_fill, size: 18, color: WaColors.akaRed) : null,
                    selected: isSelected,
                    selectedTileColor: WaColors.akaRed.withAlpha(12),
                    dense: true,
                    onTap: () {
                      setState(() => _selectedPoint = point);
                      if (MediaQuery.of(context).size.width < 900) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatView() {
    if (_displayMessages.isEmpty && _streamingText.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20)],
              ),
              child: const Icon(Icons.school_rounded, size: 80, color: WaColors.akaRed),
            ),
            const SizedBox(height: 24),
            const Text('请选择考察点', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: WaColors.sumiBlack)),
            const SizedBox(height: 8),
            const Text('点击下方按钮生成专属练习题', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: _displayMessages.length + (_streamingText.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _displayMessages.length) {
          return _buildMessageBubble(Message.text(text: _streamingText, isUser: false), isStreaming: true);
        }
        return _buildMessageBubble(_displayMessages[index]);
      },
    );
  }

  Widget _buildMessageBubble(Message message, {bool isStreaming = false}) {
    final isUser = message.isUser;
    final isThinking = message.type == MessageType.thinking;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(false),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isUser ? WaColors.skyBlue.withAlpha(20) : Colors.white,
                borderRadius: BorderRadius.circular(20).copyWith(
                  topLeft: isUser ? const Radius.circular(20) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4))
                ],
                border: Border.all(color: isUser ? WaColors.skyBlue.withAlpha(51) : Colors.grey.withAlpha(40)),
              ),
              child: isThinking 
                ? const SizedBox(
                    width: 40,
                    child: _TypingDotsIndicator(),
                  )
                : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(fontSize: 15, color: WaColors.sumiBlack, height: 1.7),
                      code: TextStyle(backgroundColor: Colors.transparent, fontSize: 13, color: Colors.indigo.shade700),
                      codeblockDecoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                      h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: WaColors.akaRed),
                      h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: WaColors.sumiBlack),
                      listBullet: const TextStyle(color: WaColors.akaRed, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: WaColors.akaRed),
                          ),
                          SizedBox(width: 8),
                          Text('Iris 正在书写...', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (isUser) _buildAvatar(true),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 5)],
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: isUser ? WaColors.skyBlue : WaColors.akaRed,
        child: Icon(isUser ? Icons.face_retouching_natural : Icons.auto_awesome_mosaic_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 15, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Material(
              color: WaColors.akaRed.withAlpha(25),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _isGenerating ? () => _chat?.stopGeneration() : _generateQuestion,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    _isGenerating ? Icons.stop_rounded : Icons.psychology_outlined,
                    color: WaColors.akaRed,
                    size: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(15),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.grey.withAlpha(30)),
                ),
                child: TextField(
                  controller: _inputController,
                  onSubmitted: _handleSend,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: '输入答案或进行对话...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _isGenerating ? null : () => _handleSend(_inputController.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isGenerating ? Colors.grey.shade300 : WaColors.akaRed,
                  shape: BoxShape.circle,
                  boxShadow: _isGenerating ? null : [
                    BoxShadow(color: WaColors.akaRed.withAlpha(60), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDotsIndicator extends StatefulWidget {
  const _TypingDotsIndicator();

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (index) {
            final double offset = (index * 0.2);
            double progress = (_controller.value - offset).remainder(1.0);
            if (progress < 0) progress += 1.0;
            
            final double opacity = progress < 0.5 ? 1.0 : 0.3;
            final double scale = progress < 0.5 ? 1.2 : 1.0;

            return Transform.scale(
              scale: scale,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: WaColors.akaRed.withOpacity(opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
