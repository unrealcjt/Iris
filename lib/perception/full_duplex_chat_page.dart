import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';
import 'package:Iris/utils/gemma_skill.dart';

enum FullDuplexState { idle, listening, thinking, speaking }

class FullDuplexChatPage extends StatefulWidget {
  const FullDuplexChatPage({super.key});

  @override
  State<FullDuplexChatPage> createState() => _FullDuplexChatPageState();
}

class _FullDuplexChatPageState extends State<FullDuplexChatPage> with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final GemmaSkill _gemmaSkill = GemmaSkill();
  
  InferenceModelSession? _chatSession; // 持久化会话以支持多轮对话
  
  FullDuplexState _state = FullDuplexState.idle;
  String _displayText = "点击开始全双工对话";
  String _aiResponseText = "";
  
  Timer? _silenceTimer;
  Timer? _vadPoller;
  bool _isUserSpeaking = false;
  bool _isProcessing = false;
  
  // VAD 阈值设置
  static const double _amplitudeThreshold = -38.0; 
  static const Duration _silenceThreshold = Duration(milliseconds: 900); 

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _stopAll();
    _vadPoller?.cancel();
    _recorder.dispose();
    _gemmaSkill.close();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _stopAll() async {
    _isProcessing = false;
    _isUserSpeaking = false;
    _vadPoller?.cancel();
    _vadPoller = null;
    _silenceTimer?.cancel();
    await _recorder.stop();
    
    // 退出页面或手动停止时完全关闭会话
    await _chatSession?.stopGeneration();
    await _chatSession?.close();
    _chatSession = null;

    await MascotController().stopSpeaking();
  }

  Future<void> _toggleConversation() async {
    if (_state == FullDuplexState.idle) {
      await _startConversation();
    } else {
      await _stopAll();
      setState(() {
        _state = FullDuplexState.idle;
        _displayText = "点击开始全双工对话";
      });
    }
  }

  Future<void> _startConversation() async {
    if (await _recorder.hasPermission()) {
      final model = MascotController().model;
      if (model == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("模型未加载，请先在设置中选择模型")),
          );
        }
        return;
      }

      // 初始化持久化的多轮对话会话
      _chatSession = await model.createSession(
        temperature: 1.0,
        topK: 64,
        topP: 0.95,
        enableAudioModality: true,
        systemInstruction: "你是一个贴心的对话助手 Iris。请听用户的语音输入，并用简洁的语言进行回应，保持对话自然流畅。直接输出你的回复内容，禁止输出任何动作描写。",
      );

      setState(() {
        _state = FullDuplexState.listening;
        _displayText = "正在聆听...";
        _aiResponseText = "";
      });
      await _startNewRecording();
      _startVAD();
    }
  }

  Future<void> _startNewRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      await Future.delayed(const Duration(milliseconds: 120));
      
      if (_state == FullDuplexState.idle) return;

      final directory = await getTemporaryDirectory();
      final path = p.join(directory.path, 'fd_${DateTime.now().millisecondsSinceEpoch}.pcm');
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
          ),
        ),
        path: path,
      );
    } catch (e) {
      debugPrint("VAD: 启动录音失败: $e");
    }
  }

  void _startVAD() {
    _vadPoller?.cancel();
    _vadPoller = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (_state == FullDuplexState.idle) return;

      try {
        if (await _recorder.isRecording()) {
          final amp = await _recorder.getAmplitude();
          double currentThreshold = (_state == FullDuplexState.speaking) 
              ? _amplitudeThreshold + 4 
              : _amplitudeThreshold;

          if (amp.current > currentThreshold) {
            _onUserSpeaking();
          } else {
            _onUserSilence();
          }
        }
      } catch (_) {}
    });
  }

  void _onUserSpeaking() {
    _silenceTimer?.cancel();
    if (!_isUserSpeaking) {
      _isUserSpeaking = true;
      if (_state == FullDuplexState.thinking || _state == FullDuplexState.speaking) {
        _interruptAI();
      }
    }
  }

  void _onUserSilence() {
    if (_isUserSpeaking) {
      if (_silenceTimer != null && _silenceTimer!.isActive) return;

      _silenceTimer = Timer(_silenceThreshold, () {
        if (_state == FullDuplexState.idle) return;
        _isUserSpeaking = false;
        if (_state == FullDuplexState.listening) {
          _processUserSpeech();
        }
      });
    }
  }

  Future<void> _interruptAI() async {
    debugPrint("VAD: !!! 打断 AI !!!");
    await _chatSession?.stopGeneration(); // 停止生成但保留会话历史
    await MascotController().stopSpeaking();

    if (mounted) {
      setState(() {
        _state = FullDuplexState.listening;
        _displayText = "正在聆听 (已打断)...";
      });
    }
    // 注意：这里不再重新调用 _startNewRecording()，
    // 因为在 _processUserSpeech 开始思考时已经启动了录音，我们希望继续使用那个录音来捕捉打断的内容。
  }

  Future<void> _processUserSpeech() async {
    if (_isProcessing) return;
    _isProcessing = true;

    String? path;
    try {
      path = await _recorder.stop();
      if (path == null) {
        _isProcessing = false;
        await _startNewRecording();
        return;
      }

      final file = File(path);
      if (!await file.exists() || (await file.length()) < 3500) {
        _isProcessing = false;
        await _startNewRecording();
        return;
      }

      setState(() {
        _state = FullDuplexState.thinking;
        _displayText = "Iris 正在思考...";
        _aiResponseText = "";
      });

      // 重要：在思考阶段也开启录音，以便 VAD 能够检测到打断
      await _startNewRecording();

      final Uint8List rawBytes = await file.readAsBytes();
      final processedBytes = _processAudioData(rawBytes);
      
      // 使用持久会话发送音频消息，保持上下文
      final message = Message.withAudio(text: "", audioBytes: processedBytes);
      await _chatSession?.addQueryChunk(message);
      final chatStream = _chatSession?.getResponseAsync();
      
      String fullResponse = "";
      if (chatStream != null) {
        await for (final chunk in chatStream) {
          if (chunk.endsWith('<channel|>')) {
            continue;
          }
          else {
            if (_state != FullDuplexState.thinking && _state != FullDuplexState.speaking) break;

            if (_state == FullDuplexState.thinking) {
              setState(() {
                _state = FullDuplexState.speaking;
                _displayText = "Iris 正在回答...";
              });
            }
            setState(() {
              _aiResponseText += chunk;
              fullResponse += chunk;
            });
          }
        }
      }

      if (fullResponse.isNotEmpty && _state == FullDuplexState.speaking) {
        await _startNewRecording();
        // final bytes = await _ttsService.getAudioBytes(fullResponse, voiceName: 'ja-JP-NanamiNeural');
        // if (bytes != null && _state == FullDuplexState.speaking) {
        //   await _ttsService.playSegments([bytes]);
        // }
        print("音频播放");
        await MascotController().speak(fullResponse);
      }
    } catch (e) {
      debugPrint("VAD: 处理异常: $e");
    } finally {
      _isProcessing = false;
      if (mounted && _state != FullDuplexState.idle && _state != FullDuplexState.listening) {
        setState(() {
          _state = FullDuplexState.listening;
          _displayText = "正在聆听...";
        });
        await _startNewRecording();
      }
      if (path != null) { try { File(path).delete(); } catch (_) {} }
    }
  }

  Uint8List _processAudioData(Uint8List rawBytes) {
    return _createWavHeader(rawBytes, 16000);
  }

  Uint8List _createWavHeader(Uint8List pcmData, int sampleRate) {
    final int fileSize = pcmData.length + 36;
    final ByteData header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61);
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
        title: const Text('全双工对话', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.2),
              colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            const Spacer(flex: 2),
            _buildStatusIndicator(colorScheme),
            const Spacer(),
            _buildChatBubble(colorScheme),
            const Spacer(),
            _buildControlPanel(colorScheme),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(ColorScheme colorScheme) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            double size = 180 + (20 * _pulseController.value);
            if (_state == FullDuplexState.thinking) size = 200;
            if (_state == FullDuplexState.speaking) size = 180 + (40 * _pulseController.value);
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: _getGradientColors(colorScheme)),
                boxShadow: [
                  BoxShadow(
                    color: _getGradientColors(colorScheme).first.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 15 * _pulseController.value,
                  )
                ],
              ),
              child: Center(
                child: Icon(_getStateIcon(), size: 72, color: Colors.white),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        Text(
          _displayText,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface, letterSpacing: 1.2),
        ),
      ],
    );
  }

  List<Color> _getGradientColors(ColorScheme colorScheme) {
    switch (_state) {
      case FullDuplexState.idle: return [Colors.grey.shade400, Colors.grey.shade600];
      case FullDuplexState.listening: return [Colors.blueAccent, Colors.blue.shade800];
      case FullDuplexState.thinking: return [Colors.purpleAccent, Colors.deepPurple.shade700];
      case FullDuplexState.speaking: return [Colors.orangeAccent, Colors.deepOrange.shade800];
    }
  }

  IconData _getStateIcon() {
    switch (_state) {
      case FullDuplexState.idle: return Icons.mic_none_rounded;
      case FullDuplexState.listening: return Icons.mic_rounded;
      case FullDuplexState.thinking: return Icons.psychology_rounded;
      case FullDuplexState.speaking: return Icons.graphic_eq_rounded;
    }
  }

  Widget _buildChatBubble(ColorScheme colorScheme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(28),
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [BoxShadow(color: colorScheme.primary.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 15))],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_aiResponseText.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.auto_awesome, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text("Iris", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ]),
              const SizedBox(height: 12),
              Text(_aiResponseText, style: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w500)),
            ] else if (_state == FullDuplexState.thinking) ...[
              const Center(child: Padding(padding: EdgeInsets.only(top: 40), child: CircularProgressIndicator(strokeWidth: 2)))
            ] else ...[
               const Center(child: Padding(padding: EdgeInsets.only(top: 40), child: Text("像通话一样直接说吧...", style: TextStyle(color: Colors.grey, fontSize: 16, fontStyle: FontStyle.italic))))
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _toggleConversation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _state == FullDuplexState.idle ? colorScheme.primary : Colors.redAccent,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: (_state == FullDuplexState.idle ? colorScheme.primary : Colors.redAccent).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Icon(_state == FullDuplexState.idle ? Icons.power_settings_new_rounded : Icons.stop_rounded, size: 40, color: Colors.white),
      ),
    );
  }
}
