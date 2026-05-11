import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

enum AudioState { initial, recording, selected, processing, result }

abstract class AudioBaseState<T extends StatefulWidget> extends State<T> {
  final AudioRecorder recorder = AudioRecorder();
  
  String? audioPath;
  Uint8List? audioBytes;
  String resultText = "";
  AudioState audioState = AudioState.initial;
  
  List<File> availableModels = [];
  File? currentModelFile;

  @override
  void initState() {
    super.initState();
    loadModelFiles();
  }

  @override
  void dispose() {
    recorder.dispose();
    super.dispose();
  }

  Future<void> loadModelFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final modelDir = Directory(p.join(directory.path, 'models'));
    if (await modelDir.exists()) {
      setState(() {
        availableModels = modelDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.litertlm'))
            .toList();
        if (availableModels.isNotEmpty) {
           currentModelFile = availableModels.first;
        }
      });
    }
  }

  Future<void> startRecording() async {
    try {
      if (await recorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = p.join(directory.path, 'temp_audio.pcm');
        
        // 强制使用 16bit-PCM 编码，采样率 16kHz
        await recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );
        setState(() {
          audioState = AudioState.recording;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始录音失败: $e')),
        );
      }
    }
  }

  Future<void> stopRecording() async {
    try {
      final path = await recorder.stop();
      if (path != null) {
        final file = File(path);
        final Uint8List rawBytes = await file.readAsBytes();

        // 将 16位 PCM 字节转为 [-1.0, 1.0] 浮点型数据并添加 WAV 头
        final processedBytes = _processAudioData(rawBytes);

        setState(() {
          audioPath = path;
          audioBytes = processedBytes;
          audioState = AudioState.selected;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('停止录音失败: $e')),
        );
      }
    }
  }

  Uint8List _processAudioData(Uint8List rawBytes) {
    // 将 16位 PCM 字节转为 [-1.0, 1.0] 浮点型数据
    final int lengthInShorts = rawBytes.lengthInBytes ~/ 2;
    final Float32List float32Bytes = Float32List(lengthInShorts);
    final ByteData byteData = rawBytes.buffer.asByteData();

    for (int i = 0; i < lengthInShorts; i++) {
      int sample = byteData.getInt16(i * 2, Endian.little);
      float32Bytes[i] = sample / 32768.0;
    }

    // 封装成带 Header 的 WAV 字节流 (IEEE Float 格式, 16kHz)
    return _createWavHeader(float32Bytes.buffer.asUint8List(), 16000);
  }

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

    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 3, Endian.little); // Format: 3 (IEEE Float)
    header.setUint16(22, 1, Endian.little); // Channels: 1
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 4, Endian.little);
    header.setUint16(32, 4, Endian.little);
    header.setUint16(34, 32, Endian.little);

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

  void reset() {
    setState(() {
      audioPath = null;
      audioBytes = null;
      resultText = "";
      audioState = AudioState.initial;
    });
  }

  void showModelPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择音频模型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (availableModels.isEmpty)
              const Text('未发现 .litertlm 模型，请先在设置中导入', style: TextStyle(color: Colors.grey))
            else
              ...availableModels.map((file) => ListTile(
                title: Text(p.basename(file.path)),
                selected: currentModelFile?.path == file.path,
                trailing: currentModelFile?.path == file.path ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () {
                  setState(() => currentModelFile = file);
                  Navigator.pop(context);
                },
              )),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget buildInitialView({
    required String title,
    required String description,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 80, color: colorScheme.primary),
            ),
            const SizedBox(height: 32),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: startRecording,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('开始录制语音'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildRecordingView({required ColorScheme colorScheme}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('正在聆听...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          Stack(
            alignment: Alignment.center,
            children: [
               Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
               Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
              IconButton(
                iconSize: 64,
                icon: const Icon(Icons.stop_rounded, color: Colors.redAccent),
                onPressed: stopRecording,
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Text('录制完成后点击停止', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget buildSelectedView({required ColorScheme colorScheme, required VoidCallback onConfirm}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.audiotrack_rounded, size: 80, color: Colors.green),
            ),
            const SizedBox(height: 32),
            const Text(
              '语音录制完成',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '您可以开始翻译这段语音内容',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 64),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: reset,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('重录'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: colorScheme.outline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('开始翻译'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildProcessingView({required String message, required ColorScheme colorScheme}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
