import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
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
  
  List<File> _availableModels = [];
  File? _currentModelFile;
  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 模式选择：快速 vs 思考
  bool _isThinkingMode = false;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _chatSession?.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    await _loadModelFiles();
    if (_availableModels.isNotEmpty) {
      // 优先选择包含 e2b 的模型，否则选第一个
      final e2bModel = _availableModels.firstWhere(
        (f) => f.path.toLowerCase().contains('e2b'),
        orElse: () => _availableModels.first,
      );
      _loadModel(e2bModel);
    } else {
      setState(() {
        _loadingStatus = "未找到可用模型，请先在模型设置中添加 .litertlm 文件";
      });
    }
  }

  Future<void> _loadModelFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final modelDir = Directory(p.join(directory.path, 'models'));
    if (await modelDir.exists()) {
      _availableModels = modelDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.litertlm'))
          .toList();
    }
  }

  Future<void> _loadModel(File modelFile) async {
    if (_isGenerating) return;
    
    setState(() {
      _isLoadingModel = true;
      _currentModelFile = modelFile;
      _loadingStatus = "正在配置 ${_isThinkingMode ? "思考" : "快速"} 引擎...";
    });

    try {
      // 1. 先彻底关闭并清空旧会话，释放 Native 资源
      if (_chatSession != null) {
        await _chatSession!.close();
        _chatSession = null;
      }
      
      // 给 Native 层一点点时间释放内存/句柄
      await Future.delayed(const Duration(milliseconds: 300));

      // 2. Install (挂载新模型)
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(modelFile.path)
          .install();
      
      // 3. 获取活动模型
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      );
      
      // 4. 创建新会话 (支持思考模式)
      final session = await model.createChat(
        isThinking: _isThinkingMode,
      );

      setState(() {
        _chatSession = session;
        _isLoadingModel = false;
        // 切换模型后清空对话历史以保证上下文干净
        _messages.clear();
      });
    } catch (e) {
      debugPrint("模型切换失败: $e");
      setState(() {
        _loadingStatus = "模型加载失败: $e";
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
        title: Column(
          children: [
            const Text('智能对话', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (_currentModelFile != null)
              Text(
                p.basename(_currentModelFile!.path),
                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_suggest_outlined),
            onPressed: _showModelPicker,
          )
        ],
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
      if (_currentModelFile != null) _loadModel(_currentModelFile!);
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

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("切换模型", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._availableModels.map((file) => ListTile(
              leading: const Icon(Icons.model_training),
              title: Text(p.basename(file.path)),
              selected: _currentModelFile?.path == file.path,
              onTap: () async {
                if (_currentModelFile?.path == file.path) {
                  Navigator.pop(context);
                  return;
                }

                bool confirm = true;
                if (_messages.isNotEmpty) {
                  confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('确认切换'),
                          content: const Text('切换模型将清空当前所有对话记录，确定要继续吗？'),
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

                final navigator = Navigator.of(context);
                if (confirm && mounted) {
                  navigator.pop();
                  _loadModel(file);
                }
              },
            )),
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
