import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EdgeTtsService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<Uint8List> _playQueue = [];
  bool _isQueuePlaying = false;
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);

  /// 生成语音并播放 (单次直接播放，并等待播放完成)
  Future<void> speak(String text, {String? voiceName, rate="+0%", volume="+0%", pitch="+0Hz"}) async {
    final bytes = await getAudioBytes(text, voiceName: voiceName, rate: rate, volume: volume, pitch: pitch);
    if (bytes != null) {
      await stop(); // 先停止之前的播放
      isPlayingNotifier.value = true;
      try {
        await _audioPlayer.play(BytesSource(bytes));
        // 等待播放完成，或者直到播放器状态变为 stopped/paused
        await Future.any([
          _audioPlayer.onPlayerComplete.first,
          _audioPlayer.onPlayerStateChanged.firstWhere((state) => state == PlayerState.stopped || state == PlayerState.paused),
        ]);
      } catch (e) {
        debugPrint('Edge TTS 播放失败: $e');
      } finally {
        isPlayingNotifier.value = false;
      }
    }
  }

  /// 将音频片段加入队列并自动开始播放
  Future<void> enqueueAndPlay(Uint8List bytes) async {
    _playQueue.add(bytes);
    if (!_isQueuePlaying) {
      _processQueue();
    }
  }

  /// 顺序处理队列中的音频
  Future<void> _processQueue() async {
    _isQueuePlaying = true;
    isPlayingNotifier.value = true;
    while (_playQueue.isNotEmpty) {
      final bytes = _playQueue.removeAt(0);
      try {
        await _audioPlayer.play(BytesSource(bytes));
        // 等待当前片段播放完成
        await _audioPlayer.onPlayerComplete.first;
      } catch (e) {
        print('Edge TTS 播放片段失败: $e');
      }
    }
    isPlayingNotifier.value = false;
    _isQueuePlaying = false;
  }

  /// 停止播放并清空队列
  Future<void> stop() async {
    _playQueue.clear();
    await _audioPlayer.stop();
    _isQueuePlaying = false;
  }

  /// 仅生成音频字节而不播放
  Future<Uint8List?> getAudioBytes(String text, {String? voiceName, String? rate, String? volume, String? pitch}) async {
    // 优先使用传入参数，否则尝试从持久化存储中读取全局设置
    String finalRate = rate ?? "+0%";
    String finalVolume = volume ?? "+0%";
    String finalPitch = pitch ?? "+0Hz";

    if (rate == null || volume == null || pitch == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (rate == null) finalRate = prefs.getString('tts_rate') ?? "+0%";
        if (volume == null) finalVolume = prefs.getString('tts_volume') ?? "+0%";
        if (pitch == null) finalPitch = prefs.getString('tts_pitch') ?? "+0Hz";
      } catch (e) {
        debugPrint('TTS 读取持久化设置失败: $e');
      }
    }

    final selectedVoice = voiceName ?? 'zh-CN-XiaoxiaoNeural';
    final communicate = Communicate(
      text: text,
      voice: selectedVoice,
      rate: finalRate,
      volume: finalVolume,
      pitch: finalPitch,
    );

    List<int> audioBytes = [];

    try {
      await for (final chunk in communicate.stream()) {
        if (chunk.type == "audio" && chunk.audioData != null) {
          audioBytes.addAll(chunk.audioData!);
        }
      }
      return audioBytes.isNotEmpty ? Uint8List.fromList(audioBytes) : null;
    } catch (e) {
      print('Edge TTS 生成失败: $e');
      return null;
    }
  }

  /// 顺序播放多个音频片段 (一次性传入列表)
  Future<void> playSegments(List<Uint8List> segments) async {
    await stop();
    isPlayingNotifier.value = true;
    for (var segment in segments) {
      await _audioPlayer.play(BytesSource(segment));
      await _audioPlayer.onPlayerComplete.first;
    }
    isPlayingNotifier.value = false;
  }

  /// 搜索可用声音
  Future<List<Voice>> getVoices() async {
    try {
      return await listVoices();
    } catch (e) {
      print('获取声音列表失败: $e');
      return [];
    }
  }

  /// 释放播放器资源
  void dispose() {
    stop();
    _audioPlayer.dispose();
  }
}
