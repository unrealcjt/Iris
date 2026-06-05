import 'dart:io';
import 'dart:typed_data';
import 'package:Iris/iris_assistant/mascot_controller.dart';
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
    MascotController().addListener(_onMascotChanged);
    _initChat();
  }

  @override
  void dispose() {
    MascotController().removeListener(_onMascotChanged);
    _chatSession?.close();
    _audioRecorder.dispose();
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
      _loadingStatus = "正在配置语音引擎...";
    });

    try {
      if (_chatSession != null) {
        await _chatSession!.close();
        _chatSession = null;
      }

      final model = MascotController().model;
      if (model != null) {
        _chatSession = await model.createChat(
          supportAudio: true,
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
        title: const Text('音频交互', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  if (msg.text.isNotEmpty)
                    isUser
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
}
