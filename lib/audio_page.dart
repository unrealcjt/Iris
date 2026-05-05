import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AudioPage extends StatefulWidget {
  const AudioPage({super.key});

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> {
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();

  List<File> _availableModels = [];
  File? _currentModelFile;
  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 录音控制器
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  String? _recordedFilePath;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _initChat();
  }

  @override
  void dispose() {
    _chatSession?.close();
    _audioRecorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    await _loadModelFiles();
    if (_availableModels.isNotEmpty) {
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
      _loadingStatus = "正在切换模型 ${p.basename(modelFile.path)}...";
    });

    try {
      if (_chatSession != null) {
        await _chatSession!.close();
        _chatSession = null;
      }

      await Future.delayed(const Duration(milliseconds: 300));

      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(modelFile.path)
          .install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
        supportAudio: true,
      );

      final session = await model.createChat(
        supportAudio: true,
      );

      setState(() {
        _chatSession = session;
        _isLoadingModel = false;
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

  // 开始录音
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = p.join(directory.path, 'audio_record.m4a');

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits, // 强制使用最底层的 16bit-PCM 编码
            sampleRate: 16000,               // 采样率设为 16kHz
            numChannels: 1,                  // 单声道
          ),
          path: filePath,
        );

        setState(() {
          _isRecording = true;
          _recordedFilePath = null;
        });
      }
    } catch (e) {
      debugPrint('录音启动失败: $e');
    }
  }

  // 停止录音
  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });

      // 录音完成后，自动处理并发送给大模型
      if (_recordedFilePath != null) {
        await _sendAudioMessage();
      }
    } catch (e) {
      debugPrint('停止录音失败: $e');
    }
  }

  // 发送录音消息
  Future<void> _sendAudioMessage() async {
    if (_recordedFilePath == null || _chatSession == null || _isGenerating) return;

    final file = File(_recordedFilePath!);
    final Uint8List rawBytes = await file.readAsBytes();

    // 将 16位 PCM 字节转为 [-1.0, 1.0] 浮点型数据
    final int lengthInShorts = rawBytes.lengthInBytes ~/ 2;
    final Float32List float32Bytes = Float32List(lengthInShorts);
    final ByteData byteData = rawBytes.buffer.asByteData();

    for (int i = 0; i < lengthInShorts; i++) {
      // 按照小端模式 (Endian.little) 读取 16-bit 整数
      int sample = byteData.getInt16(i * 2, Endian.little);
      // 归一化到 [-1.0, 1.0] 范围
      float32Bytes[i] = sample / 32768.0;
    }

    // 封装成带 Header 的 WAV 字节流 (IEEE Float 格式)
    final Uint8List wavBytes = _createWavHeader(float32Bytes.buffer.asUint8List(), 16000);

    final userMsg = Message.withAudio(
      audioBytes: wavBytes,
      text: "",
      isUser: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(Message.text(text: "", isUser: false));
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      await _chatSession!.addQueryChunk(userMsg);
      final stream = _chatSession!.generateChatResponseAsync(); // 可替换为 generateChatResponseAsync

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

  // 构建 WAV 头的辅助函数 (针对 IEEE Float 格式)
  Uint8List _createWavHeader(Uint8List pcmData, int sampleRate) {
    final int fileSize = pcmData.length + 36;
    final ByteData header = ByteData(44);

    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Size of fmt chunk
    header.setUint16(20, 3, Endian.little); // Format: 3 (IEEE Float)
    header.setUint16(22, 1, Endian.little); // Channels: 1
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 4, Endian.little); // Byte rate (sampleRate * channels * bytesPerSample)
    header.setUint16(32, 4, Endian.little); // Block align (channels * bytesPerSample)
    header.setUint16(34, 32, Endian.little); // Bits per sample

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, pcmData.length, Endian.little);

    final Uint8List result = Uint8List(44 + pcmData.length);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(44, pcmData);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Column(
          children: [
            const Text('音频交互', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
          Icon(Icons.record_voice_over, size: 64, color: colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text("欢迎使用音频交互模块", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("按住下方按钮录制语音，开始端到端多模态对话", style: TextStyle(color: Colors.grey)),
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

    Uint8List? audioBytes;
    try {
      audioBytes = msg.audioBytes;
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
                  if (audioBytes != null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic, size: 20, color: Colors.blueAccent),
                          SizedBox(width: 6),
                          Text("已发送语音片段", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: SafeArea(
        child: Center(
          child: GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecording(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 48),
              decoration: BoxDecoration(
                color: _isRecording ? Colors.redAccent : colorScheme.primary,
                borderRadius: BorderRadius.circular(36),
                boxShadow: _isRecording
                    ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4), blurRadius: 16)]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isRecording ? Icons.fiber_manual_record : Icons.mic,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isRecording ? "正在录音... 松开发送" : "按住 说话实练",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
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

                if (confirm && mounted) {
                  Navigator.pop(context);
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