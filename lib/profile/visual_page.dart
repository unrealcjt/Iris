import 'dart:io';
import 'dart:typed_data';
import 'package:Iris/iris_assistant/mascot_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class VisualPage extends StatefulWidget {
  const VisualPage({super.key});

  @override
  State<VisualPage> createState() => _VisualPageState();
}

class _VisualPageState extends State<VisualPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 图片选择器
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

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
        _loadingStatus = "未找到可用模型，请先导入 .litertlm 文件";
      });
    }
  }

  Future<void> _loadSession() async {
    if (_isGenerating) return;

    setState(() {
      _isLoadingModel = true;
      _loadingStatus = "正在配置视觉引擎...";
    });

    try {
      if (_chatSession != null) {
        await _chatSession!.close();
        _chatSession = null;
      }

      final model = MascotController().model;
      if (model != null) {
        _chatSession = await model.createChat(
          supportImage: true,
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

  // 图像选择处理：相机或相册
  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  // 发送消息（支持纯文本与带有图像的多模态）
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _selectedImage == null) || _chatSession == null || _isGenerating) return;

    _controller.clear();

    // 构建发送给模型的对象
    Message userMsg;
    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      // 如果有图片，同时发送图片字节块
      userMsg = Message.withImage(
        text: text,
        imageBytes: Uint8List.fromList(bytes),
        isUser: true,
      );
    } else {
      userMsg = Message.text(text: text, isUser: true);
    }

    setState(() {
      _messages.add(userMsg);
      _messages.add(Message.text(text: "", isUser: false)); // AI 回复占位
      _isGenerating = true;
      // 清理临时选择的图片
      _selectedImage = null;
    });
    _scrollToBottom();

    try {
      await _chatSession!.addQueryChunk(userMsg);
      final stream = _chatSession!.generateChatResponseAsync();

      String fullResponse = "";
      await for (final response in stream) {
        if (response is TextResponse) {
          fullResponse += response.token;
          setState(() {
            _messages[_messages.length - 1] = Message.text(text: fullResponse, isUser: false);
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
        title: const Text('视觉对话', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _messages.isEmpty && !_isLoadingModel
                    ? _buildWelcomeGuide(colorScheme)
                    : _buildMessageList(),
              ),
              if (_selectedImage != null) _buildImagePreviewCard(),
              _buildInputArea(colorScheme),
            ],
          ),
          if (_isLoadingModel) _buildLoadingOverlay(colorScheme),
        ],
      ),
    );
  }

  Widget _buildImagePreviewCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(_selectedImage!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text("已选择要发送的图片", style: TextStyle(fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _selectedImage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surface.withOpacity(0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(_loadingStatus, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text("首次加载大型模型可能需要较长时间", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
          Icon(Icons.camera_alt, size: 64, color: colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text("欢迎使用视觉对话", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("拍摄照片或从相册选择图片，开始多模态对话", style: TextStyle(color: Colors.grey)),
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

    // 检查是否包含图像数据
    Uint8List? imageBytes;
    try {
      imageBytes = msg.imageBytes; // 获取 Message 对象的图像
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(Icons.bolt, colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: isUser ? const Radius.circular(0) : null,
                  bottomLeft: !isUser ? const Radius.circular(0) : null,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 如果存在图像字节，则解析并绘制图像
                  if (imageBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          imageBytes,
                          width: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  // 如果包含文本则显示文本
                  if (msg.text != null && msg.text!.isNotEmpty)
                    isUser
                        ? Text(
                            msg.text!,
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 15,
                            ),
                          )
                        : MarkdownBody(
                            data: msg.text!,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                ],
              ),
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
            // 相机按钮
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () => _pickImage(ImageSource.camera),
              color: colorScheme.primary,
            ),
            // 相册按钮
            IconButton(
              icon: const Icon(Icons.photo_library),
              onPressed: () => _pickImage(ImageSource.gallery),
              color: colorScheme.primary,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isLoadingModel && !_isGenerating,
                decoration: InputDecoration(
                  hintText: '描述你看到的画面...',
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
