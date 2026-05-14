import 'dart:io';
import 'package:Iris/iris_assistant/mascot_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 模式选择：快速 vs 思考
  bool _isThinkingMode = false;

  @override
  void initState() {
    super.initState();
    MascotController().addListener(_onMascotChanged);
    _initChat();
  }

  @override
  void dispose() {
    MascotController().removeListener(_onMascotChanged);
    _chatSession?.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMascotChanged() {
    if (_chatSession == null && MascotController().model != null) {
      _initChat();
    }
  }

  Future<void> _initChat() async {
    if (MascotController().model == null) {
      setState(() {
        _isLoadingModel = true;
        _loadingStatus = "正在等待模型加载...";
      });
      await MascotController().init();
    }
    
    if (MascotController().model != null) {
      _loadSession();
    } else {
      setState(() {
        _isLoadingModel = false;
        _loadingStatus = "未找到可用模型，请先导入 .litertlm 文件";
      });
    }
  }

  Future<void> _loadSession() async {
    if (_isGenerating) return;
    
    setState(() {
      _isLoadingModel = true;
      _loadingStatus = "正在配置 ${_isThinkingMode ? "思考" : "快速"} 引擎...";
    });

    try {
      if (_chatSession != null) {
        await _chatSession!.close();
        _chatSession = null;
      }
      
      final model = MascotController().model;
      if (model != null) {
        _chatSession = await model.createChat(
          isThinking: _isThinkingMode,
        );
      }

      setState(() {
        _isLoadingModel = false;
        _messages.clear();
      });
    } catch (e) {
      debugPrint("会话创建失败: $e");
      setState(() {
        _loadingStatus = "会话创建失败: $e";
        _isLoadingModel = false;
      });
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _chatSession == null || _isGenerating) return;

    _controller.clear();
    
    // 如果是思考模式，使用 Message constructor 指定类型，因为 factory hardcode 了 isUser: false
    final userMsg = _isThinkingMode 
        ? Message(text: text, isUser: true, type: MessageType.thinking)
        : Message.text(text: text, isUser: true);
    
    setState(() {
      _messages.add(userMsg);
      _messages.add(Message.text(text: "", isUser: false)); // Placeholder for AI response
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      await _chatSession!.addQueryChunk(userMsg);
      final stream = _chatSession!.generateChatResponseAsync();
      
      String fullResponse = "";
      String thinkingProcess = "";

      await for (final response in stream) {
        if (response is TextResponse) {
          fullResponse += response.token;
          setState(() {
            _messages[_messages.length - 1] = Message(
              text: fullResponse, 
              isUser: false,
              toolName: thinkingProcess.isNotEmpty ? thinkingProcess : null,
            );
          });
          _scrollToBottom();
        } else if (response is ThinkingResponse) {
          thinkingProcess += response.content;
          setState(() {
            _messages[_messages.length - 1] = Message(
              text: fullResponse,
              isUser: false,
              toolName: thinkingProcess,
            );
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      setState(() {
        _messages[_messages.length - 1] = Message.text(text: "错误: $e", isUser: false);
      });
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('智能对话', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildModeToggle(colorScheme),
              Expanded(
                child: _messages.isEmpty && !_isLoadingModel
                    ? _buildWelcomeGuide(colorScheme)
                    : _buildMessageList(),
              ),
              _buildInputArea(colorScheme),
            ],
          ),
          if (_isLoadingModel) _buildLoadingOverlay(colorScheme),
        ],
      ),
    );
  }

  Widget _buildModeToggle(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text("快速"),
              icon: Icon(Icons.bolt_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text("思考"),
              icon: Icon(Icons.psychology_rounded),
            ),
          ],
          selected: {_isThinkingMode},
          onSelectionChanged: (Set<bool> newSelection) {
            if (_isGenerating) return;
            final newVal = newSelection.first;
            if (newVal != _isThinkingMode) {
              _showChangeModeConfirm(newVal);
            }
          },
        ),
      ),
    );
  }

  void _showChangeModeConfirm(bool newVal) async {
    bool confirm = true;
    if (_messages.isNotEmpty) {
      confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('模式切换'),
              content: const Text('切换推理模式需要重置当前对话记录，确定继续吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (confirm && mounted) {
      setState(() => _isThinkingMode = newVal);
      _loadSession();
    }
  }

  Widget _buildLoadingOverlay(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surface.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(_loadingStatus, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text("正在配置推理引擎，请稍候...", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeGuide(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isThinkingMode ? Icons.psychology : Icons.auto_awesome, 
            size: 64, 
            color: colorScheme.primary.withValues(alpha: 0.5)
          ),
          const SizedBox(height: 16),
          Text(
            _isThinkingMode ? "思考模式已就绪" : "你好！我是 Iris 智能助理", 
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
          ),
          Text(
            _isThinkingMode ? "我将提供更深层的逻辑解析" : "基于 Gemma-4 离线模型，隐私且高效", 
            style: const TextStyle(color: Colors.grey)
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(Message msg) {
    final isUser = msg.isUser;
    final colorScheme = Theme.of(context).colorScheme;
    
    // 借用 toolName 传递思考过程
    final thinking = msg.toolName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(Icons.bolt, colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (thinking != null && thinking.isNotEmpty)
                  _ThinkingBlock(thinking: thinking),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomRight: isUser ? const Radius.circular(0) : null,
                      bottomLeft: !isUser ? const Radius.circular(0) : null,
                    ),
                  ),
                  child: isUser 
                    ? Text(
                        msg.text,
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontSize: 15,
                        ),
                      )
                    : MarkdownBody(
                        data: msg.text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 15,
                            height: 1.5,
                          ),
                          code: TextStyle(
                            backgroundColor: colorScheme.surfaceContainer,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) _buildAvatar(Icons.person, colorScheme.secondary),
        ],
      ),
    );
  }

  Widget _buildAvatar(IconData icon, Color color) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isLoadingModel && !_isGenerating,
                decoration: InputDecoration(
                  hintText: _isThinkingMode ? '深度思考中提问...' : '输入消息...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: (_isGenerating || _isLoadingModel) ? null : _sendMessage,
              icon: Icon(_isGenerating ? Icons.hourglass_empty : Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingBlock extends StatefulWidget {
  final String thinking;
  const _ThinkingBlock({required this.thinking});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high, size: 14, color: colorScheme.secondary),
                const SizedBox(width: 4),
                const Text("思考中...", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14,
                  color: colorScheme.secondary,
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            Text(
              widget.thinking,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
