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
  
  // 防死循环计数器
  int _recursiveToolCallCount = 0;
  static const int _maxRecursiveCalls = 2;

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
          modelType: ModelType.gemma4,
          supportsFunctionCalls: true,
          systemInstruction: "你是一个名为 Iris 的助理。请使用 'speak' 工具来回答用户。请在一次回复中同时完成工具调用和对应的文字输出。收到工具执行成功的反馈后，请直接结束对话，不要重复调用工具。",
          tools: [
            const Tool(
              name: 'speak',
              description: '将回复文本转换为语音播放给用户听。',
              parameters: {
                'type': 'object',
                'properties': {
                  'text': {
                    'type': 'string',
                    'description': '需要播放的文本内容',
                  },
                },
                'required': ['text'],
              },
            ),
          ],
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
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      _recursiveToolCallCount = 0;
      await _chatSession!.addQueryChunk(userMsg);
      await _processModelResponse();
    } catch (e) {
      debugPrint("消息发送失败: $e");
      setState(() {
        _messages.add(Message.text(text: "错误: $e", isUser: false));
      });
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _processModelResponse() async {
    if (_recursiveToolCallCount > _maxRecursiveCalls) {
      debugPrint("检测到潜在的工具调用死循环，已强制中断。");
      return;
    }

    debugPrint("开始获取模型响应流...");
    final stream = _chatSession!.generateChatResponseAsync();
    
    String fullResponse = "";
    String thinkingProcess = "";
    bool hasFunctionCall = false;
    int? aiMsgIndex;

    await for (final response in stream) {
      if (response is TextResponse || response is ThinkingResponse) {
        if (aiMsgIndex == null) {
          setState(() {
            _messages.add(Message.text(text: "", isUser: false));
            aiMsgIndex = _messages.length - 1;
          });
        }

        if (response is TextResponse) {
          fullResponse += response.token;
        } else if (response is ThinkingResponse) {
          thinkingProcess += response.content;
        }

        final displayShowing = _cleanResponseText(fullResponse);

        setState(() {
          _messages[aiMsgIndex!] = Message(
            text: displayShowing, 
            isUser: false,
            // 如果清理后没有文本且没有思考，先标记为 toolCall 隐藏，防止显示空气泡或 JSON
            type: (displayShowing.isEmpty && thinkingProcess.isEmpty) ? MessageType.toolCall : MessageType.text,
            toolName: thinkingProcess.isNotEmpty ? thinkingProcess : null,
          );
        });
        _scrollToBottom();
      } else if (response is FunctionCallResponse) {
        debugPrint("捕获到工具调用: ${response.name}");
        hasFunctionCall = true;
        _recursiveToolCallCount++;
        // 如果当前消息气泡清理后是空的，说明它只包含工具调用 JSON，隐藏它
        if (aiMsgIndex != null && _cleanResponseText(fullResponse).isEmpty) {
          setState(() {
            _messages[aiMsgIndex!] = _messages[aiMsgIndex!].copyWith(type: MessageType.toolCall);
          });
        }
        await _handleFunctionCall(response);
      } else if (response is ParallelFunctionCallResponse) {
        debugPrint("捕获到并行工具调用: ${response.calls.length} 个");
        hasFunctionCall = true;
        if (aiMsgIndex != null && _cleanResponseText(fullResponse).isEmpty) {
          setState(() {
            _messages[aiMsgIndex!] = _messages[aiMsgIndex!].copyWith(type: MessageType.toolCall);
          });
        }
        for (final call in response.calls) {
          await _handleFunctionCall(call);
        }
      }
    }

    if (hasFunctionCall) {
      debugPrint("工具执行完毕，请求模型处理后续结果...");
      await _processModelResponse();
    }
  }

  String _cleanResponseText(String text) {
    // 移除 Gemma 4 的工具调用标记及其内部 JSON 内容
    // 匹配 <|tool_call|>...<|tool_call|> 及其中的内容
    String cleaned = text
        .replaceAll(RegExp(r'<\|tool_call\|>.*?<\|tool_call\|>', dotAll: true), '')
        .replaceAll(RegExp(r'<\|.*?\|>', dotAll: true), '') // 移除其他可能的 <|...|> 标记
        .trim();

    // 如果清理后剩下的内容看起来像是一个单独的 JSON 对象（通常是未被标记完全的工具调用）
    if (cleaned.startsWith('{') && cleaned.endsWith('}') && cleaned.contains('"name"')) {
      return "";
    }

    return cleaned;
  }

  Future<void> _handleFunctionCall(FunctionCallResponse call) async {
    debugPrint("执行工具逻辑: ${call.name}, 参数: ${call.args}");
    if (call.name == 'speak') {
      final textToSpeak = call.args['text'] as String?;
      if (textToSpeak != null && textToSpeak.isNotEmpty) {
        setState(() {
          _messages.add(Message.systemInfo(text: "Iris 正在为您播报...", icon: "volume_up"));
        });
        _scrollToBottom();
        
        // 调用看板娘控制器的播放逻辑，它会自动处理多语言配音
        await MascotController().speak(textToSpeak);
        
        // 向模型反馈结果
        await _chatSession!.addQueryChunk(Message.toolResponse(
          toolName: 'speak',
          response: {'status': 'success'},
        ));
      }
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
    final bool showThinking = _isGenerating && 
        (_messages.isEmpty || _messages.last.isUser || _messages.last.type == MessageType.toolResponse);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildWaitingBubble();
        }
        
        final msg = _messages[index];
        // 隐藏模型内部的工具调用和响应消息，只显示文本、思考过程和系统提示
        if (msg.type == MessageType.toolCall || msg.type == MessageType.toolResponse) {
          return const SizedBox.shrink();
        }
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildWaitingBubble() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(Icons.bolt, colorScheme.primary),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20).copyWith(
                bottomLeft: const Radius.circular(0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _TypingIndicator(),
                const SizedBox(width: 8),
                Text(
                  "Iris 正在思考...",
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    if (msg.type == MessageType.systemInfo) {
      return _buildSystemInfo(msg);
    }
    
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

  Widget _buildSystemInfo(Message msg) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isSpeaking = msg.toolName == 'volume_up';
    
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSpeaking)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.secondary),
                  ),
                ),
              )
            else
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colorScheme.secondary,
              ),
            if (!isSpeaking) const SizedBox(width: 8),
            Text(
              msg.text,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final double opacity = ((_controller.value * 3 - index).remainder(3) / 3).clamp(0.2, 1.0);
            return Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
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
