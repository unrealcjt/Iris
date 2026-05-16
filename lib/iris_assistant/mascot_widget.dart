import 'package:Iris/custom_component/iris_selection_area.dart';
import 'package:Iris/iris_assistant/gojuon_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'mascot_controller.dart';

class IrisMascotOverlay extends StatefulWidget {
  const IrisMascotOverlay({super.key});

  @override
  State<IrisMascotOverlay> createState() => _IrisMascotOverlayState();
}

class _IrisMascotOverlayState extends State<IrisMascotOverlay> {
  final MascotController _controller = MascotController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _translateInputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late VideoPlayerController _talkingController;
  bool _wasExpanded = false;
  bool _isModelSelectionOpen = false; // 用于控制模型选择界面的显示
  bool _isLanguageSelectionOpen = false; // 用于控制翻译语言选择界面的显示
  bool _isTextInputOpen = false; // 用于控制翻译文本输入界面的显示
  bool _isActionMenuOpen = false; // 用于控制功能集菜单的展开

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
    _wasExpanded = _controller.isExpanded;
    _loadPlayer();
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _scrollController.dispose();
    _inputController.dispose();
    _translateInputController.dispose();
    _focusNode.dispose();
    _talkingController.dispose();
    super.dispose();
  }

  void _loadPlayer() {
    _talkingController = VideoPlayerController.asset(
        'assets/video/Iris_talk.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)
    )
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _talkingController.setLooping(true);
          _talkingController.pause();
          _talkingController.seekTo(Duration.zero);
        }
      });
  }

  void _onStateChanged() {
    if (!mounted) return;

    // 如果是从展开变为收起，清理焦点和内部状态
    if (_wasExpanded && !_controller.isExpanded) {
      _focusNode.unfocus();
      _isModelSelectionOpen = false;
      _isLanguageSelectionOpen = false;
      _isTextInputOpen = false;
      _isActionMenuOpen = false;
      _translateInputController.clear();
    }
    _wasExpanded = _controller.isExpanded;

    setState(() {});
    
    if (_controller.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients && !_scrollController.position.isScrollingNotifier.value) {
          try {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          } catch (_) {}
        }
      });
    }

    if (_talkingController.value.isInitialized) {
      updatePlayer();
    }
  }

  void updatePlayer() {
    if (_controller.isTalking) {
      _talkingController.play();
    } else {
      _talkingController.pause();
      _talkingController.seekTo(Duration.zero);
    }
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isNotEmpty && !_controller.isGenerating) {
      _inputController.clear();
      _controller.sendMessage(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;

    double targetLeft;
    double targetTop;

    if (_controller.mode == MascotDisplayMode.docked) {
      targetLeft = size.width / 2 - 28;
      targetTop = size.height - 100;
    } else {
      targetLeft = _controller.floatOffset.dx;
      targetTop = _controller.floatOffset.dy;
    }

    return Stack(
      children: [
        if (_controller.isExpanded && _controller.isVisible)
          GestureDetector(
            onTap: () {
              _focusNode.unfocus();
              _controller.setExpanded(false);
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, child) => Container(
                color: Colors.black.withOpacity(0.7 * value),
              ),
            ),
          ),

        if (_controller.isExpanded && _controller.isVisible) _buildExpandedPanel(context, colorScheme),

        if (!_controller.isExpanded && _controller.isVisible)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            left: targetLeft,
            top: targetTop,
            child: _buildOrb(colorScheme),
          ),
      ],
    );
  }

  Widget _buildOrb(ColorScheme colorScheme) {
    return GestureDetector(
      onPanUpdate: (details) {
        if (_controller.mode == MascotDisplayMode.floating) {
          _controller.updateOffset(details.delta);
        }
      },
      onTap: () {
        _controller.toggleExpanded();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
            border: Border.all(color: colorScheme.primary, width: 2),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
              )
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/img/Iris_Scarlet.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                Icon(Icons.auto_awesome, color: colorScheme.primary, size: 30),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(BuildContext context, ColorScheme colorScheme) {
    final size = MediaQuery.of(context).size;
    final isFullScreen = _controller.isFullScreen;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: isFullScreen ? size.width : size.width * 0.92,
          height: isFullScreen ? size.height : size.height * 0.85,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isFullScreen ? 0 : 32),
            boxShadow: [
              if (!isFullScreen) BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30)
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(child: _buildDynamicBackground()),
              
              // 关键：仅保留 Overlay 以支持 Tooltip/TextField，移除 Navigator
              Positioned.fill(
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (overlayContext) => ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) {
                          final isImmersive = _controller.isImmersive && _controller.assistantMode == MascotAssistantMode.chat;
                          return Scaffold(
                            backgroundColor: Colors.transparent,
                            resizeToAvoidBottomInset: true,
                            body: Stack(
                              children: [
                                if (!isImmersive)
                                  _buildTopBar(colorScheme)
                                else
                                  Positioned(
                                    top: 24,
                                    right: 20,
                                    child: _buildTopIconButton(
                                      icon: Icons.visibility_outlined,
                                      onTap: _controller.toggleImmersive,
                                      tooltip: "退出沉浸",
                                    ),
                                  ),

                                if (_controller.assistantMode == MascotAssistantMode.assistant)
                                  _buildAssistantActions(),

                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDialogueBox(colorScheme),
                                      const SizedBox(height: 12),
                                      if (_controller.assistantMode == MascotAssistantMode.chat)
                                        _buildInputBar(colorScheme)
                                      else
                                        const SizedBox(height: 24),
                                    ],
                                  ),
                                ),

                                if (_controller.isHistoryVisible) _buildHistoryOverlay(colorScheme),

                                if (_controller.isModelLoading)
                                  const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 20),
                                        Text("Iris 正在降临中...", style: TextStyle(color: Colors.white, fontSize: 16)),
                                      ],
                                    ),
                                  ),

                                // 自定义模型选择遮罩层，取代 showDialog
                                if (_isModelSelectionOpen) _buildModelSelectionOverlay(),
                                
                                // 语言选择遮罩层
                                if (_isLanguageSelectionOpen) _buildLanguageSelectionOverlay(),

                                // 文本输入遮罩层
                                if (_isTextInputOpen) _buildTextInputOverlay(),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Positioned(
      top: 24,
      left: 16,
      right: 16,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                _buildModeTab("Assist", MascotAssistantMode.assistant),
                _buildModeTab("Chat", MascotAssistantMode.chat),
              ],
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTopIconButton(
                icon: _controller.assistantMode == MascotAssistantMode.chat
                    ? Icons.visibility_off_outlined
                    : Icons.settings_suggest_outlined,
                onTap: () {
                  if (_controller.assistantMode == MascotAssistantMode.chat) {
                    _controller.toggleImmersive();
                  } else {
                    setState(() => _isModelSelectionOpen = true);
                  }
                },
                tooltip: _controller.assistantMode == MascotAssistantMode.chat ? "沉浸模式" : "选择模型",
              ),
              const SizedBox(width: 4),
              _buildTopIconButton(
                icon: _controller.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                onTap: _controller.toggleFullScreen,
                tooltip: "全屏",
              ),
              const SizedBox(width: 4),
              _buildTopIconButton(
                icon: Icons.history_rounded,
                onTap: _controller.toggleHistory,
                tooltip: "历史",
              ),
              const SizedBox(width: 4),
              _buildTopIconButton(
                icon: Icons.close,
                onTap: () {
                  _focusNode.unfocus();
                  _controller.setExpanded(false);
                },
                tooltip: "关闭",
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showGojuonDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,      // 点击背景关闭
      barrierLabel: "Gojuon",
      barrierColor: Colors.black54,  // 背景遮罩颜色
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        // 这里返回你之前写的那个 GojuonPanel
        return Center(
          child: GojuonPanel(
            onCharTap: (hira) {
              _controller.speak(hira);
              // 如果你想点击一个音后自动关闭，可以加 Navigator.pop(context);
            },
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        // 二次元常用的弹跳缩放效果
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildAssistantActions() {
    return Positioned(
      top: 100,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 五十音弹窗层
          GestureDetector(
            onTap: () => setState(() {
              _showGojuonDialog(context);
            }),
            child: _buildQuickAction(Icons.grid_4x4_rounded, "五十音"),
          ),
          const SizedBox(height: 12),
          
          // 功能集：使用 Row 确保所有子项都在 HitTest 区域内
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isActionMenuOpen)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(20 * (1 - value), 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSubAction(
                              icon: Icons.analytics_outlined, 
                              label: "分析", 
                              onTap: () => _handleAction(() => _controller.analyzeGrammar()),
                            ),
                            const SizedBox(width: 12),
                            _buildSubAction(
                              icon: Icons.volume_up_outlined, 
                              label: "朗读", 
                              onTap: () => _handleAction(() => _controller.speakHelpText()),
                            ),
                            const SizedBox(width: 12),
                            _buildSubAction(
                              icon: Icons.translate_rounded, 
                              label: "翻译", 
                              onTap: () => _handleAction(() {
                                if (_controller.helpText.isEmpty) {
                                  setState(() => _isTextInputOpen = true);
                                } else {
                                  setState(() => _isLanguageSelectionOpen = true);
                                }
                              }),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              
              // 主按钮
              GestureDetector(
                onTap: () => setState(() => _isActionMenuOpen = !_isActionMenuOpen),
                child: _buildQuickAction(
                  _isActionMenuOpen ? Icons.close : Icons.auto_awesome_motion_rounded, 
                  _isActionMenuOpen ? "收起" : "快捷",
                  active: _isActionMenuOpen,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildQuickAction(Icons.lightbulb_outline, "小知识"),
        ],
      ),
    );
  }

  // 子功能按钮组件
  Widget _buildSubAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      ),
    );
  }

  // 统一处理逻辑：如果点击了子功能，自动收起菜单
  void _handleAction(VoidCallback action) {
    setState(() => _isActionMenuOpen = false);
    action();
  }

  Widget _buildTextInputOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("输入要翻译的内容", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _translateInputController,
                autofocus: true,
                maxLines: 5,
                minLines: 1,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "在这里输入...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _isTextInputOpen = false);
                      _translateInputController.clear();
                    },
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final text = _translateInputController.text.trim();
                      if (text.isNotEmpty) {
                        _controller.setHelpText(text);
                        setState(() {
                          _isTextInputOpen = false;
                          _isLanguageSelectionOpen = true;
                        });
                      }
                    },
                    child: const Text("确定"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelectionOverlay() {
    final languages = ["中文", "日语", "英语", "韩语", "德语", "法语"];
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("选择目标语言", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: languages.map((lang) => InkWell(
                  onTap: () {
                    setState(() => _isLanguageSelectionOpen = false);
                    _controller.translate(targetLang: lang);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(lang, style: const TextStyle(color: Colors.white)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => setState(() => _isLanguageSelectionOpen = false),
                child: const Text("取消"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelSelectionOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("模型与语音设置", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("模型选择", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _controller.availableModels.length,
                    itemBuilder: (context, index) {
                      final model = _controller.availableModels[index];
                      final isSelected = _controller.selectedModelPath == model.path;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        title: Text(
                          p.basename(model.path),
                          style: TextStyle(color: isSelected ? Colors.pinkAccent : Colors.white70, fontSize: 14),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.pinkAccent, size: 16) : null,
                        onTap: () {
                          _controller.setModelPath(model.path);
                        },
                      );
                    },
                  ),
                ),
              ),
              const Divider(color: Colors.white10, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("语音参数调节", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: () => _controller.updateTtsParams(rate: "+0%", volume: "+0%", pitch: "+0Hz"),
                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 18, color: Colors.pinkAccent),
                    tooltip: "重置参数",
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTtsSlider(
                label: "语速",
                value: _parseTtsValue(_controller.ttsRate),
                onChanged: (v) => _controller.updateTtsParams(rate: _formatTtsValue(v, suffix: "%")),
              ),
              _buildTtsSlider(
                label: "音量",
                value: _parseTtsValue(_controller.ttsVolume),
                onChanged: (v) => _controller.updateTtsParams(volume: _formatTtsValue(v, suffix: "%")),
              ),
              _buildTtsSlider(
                label: "音高",
                value: _parseTtsValue(_controller.ttsPitch),
                onChanged: (v) => _controller.updateTtsParams(pitch: _formatTtsValue(v, suffix: "Hz")),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _isModelSelectionOpen = false),
                  child: const Text("完成配置"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTtsSlider({required String label, required double value, required ValueChanged<double> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value,
                min: -100,
                max: 100,
                divisions: 200,
                activeColor: Colors.pinkAccent,
                inactiveColor: Colors.white10,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value >= 0 ? "+${value.toInt()}" : value.toInt().toString(),
              style: const TextStyle(color: Colors.pinkAccent, fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  double _parseTtsValue(String raw) {
    final match = RegExp(r'([+-]?\d+)').firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  String _formatTtsValue(double value, {required String suffix}) {
    final valInt = value.toInt();
    final prefix = valInt >= 0 ? "+" : "";
    return "$prefix$valInt$suffix";
  }

  Widget _buildModeTab(String label, MascotAssistantMode mode) {
    final isSelected = _controller.assistantMode == mode;
    return GestureDetector(
      onTap: () {
        if (mode == MascotAssistantMode.assistant) {
          // 关闭对话
          _controller.setTalking(false);
        }
        _controller.setAssistantMode(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTopIconButton({required IconData icon, required VoidCallback onTap, String? tooltip}) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? "",
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, {bool active = false}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? Colors.pinkAccent.withOpacity(0.5) : Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: active ? Colors.pinkAccent : Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    );
  }

  Widget _buildDialogueBox(ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.pinkAccent.withOpacity(0.5), Colors.pinkAccent.withOpacity(0.0)],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                "Iris",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 2,
                  shadows: [Shadow(color: colorScheme.primary, blurRadius: 12)],
                ),
              ),
              if (_controller.assistantMode == MascotAssistantMode.chat &&
                  (!_controller.isAudioGenerating) &&
                  (!_controller.chatMessages.isEmpty))
                Positioned(
                  right: 16,
                  child: GestureDetector(
                    onTap: _controller.playExistedAudioSegments,
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              if (_controller.assistantMode == MascotAssistantMode.assistant)
                if (_controller.isGenerating)
                  Positioned(
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        _controller.stopSkillReply();
                      },
                      child: const Icon(
                        Icons.stop,
                        color: Colors.red,
                        size: 30,
                      ),
                    ),
                  )
                else
                  Positioned(
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        _controller.refreshAssistText();
                      },
                      child: const Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.pinkAccent.withOpacity(0.5),
          height: 16,
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.amber.withOpacity(0.5), thickness: 1.5, indent: 20, endIndent: 8)),
              const Icon(Icons.auto_awesome_outlined, size: 16, color: Colors.amber),
              Expanded(child: Divider(color: Colors.amber.withOpacity(0.5), thickness: 1.5, indent: 8, endIndent: 20)),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.pinkAccent.withOpacity(0.5), Colors.pinkAccent.withOpacity(0.0)],
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 30),
              child: _controller.isGenerating && _controller.currentDialogueText.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 20),
                          const _TypingIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            "Iris 正在思考...",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                        ],
                      ),
                    )
                  :
                    IrisSelectionArea(
                      child: MarkdownBody(
                        data: _controller.currentDialogueText,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.6,
                            shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                          ),
                          code: TextStyle(
                            backgroundColor: Colors.black.withOpacity(0.3),
                            color: Colors.amberAccent,
                            fontFamily: 'monospace',
                            fontSize: 18,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Row(
        children: [
          if (!_controller.isGenerating)
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.multiline,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: "想聊点什么？",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: colorScheme.primary),
                  ),
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _handleSend,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: _controller.isGenerating
                    ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryOverlay(ColorScheme colorScheme) {
    return Container(
      color: Colors.black.withOpacity(0.9),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.history_edu_rounded, color: Colors.white70),
              const SizedBox(width: 12),
              const Text("对话记录", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed: _controller.clearHistory, child: const Text("清空")),
              IconButton(onPressed: _controller.toggleHistory, icon: const Icon(Icons.close, color: Colors.white)),
            ],
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView.builder(
              itemCount: _controller.chatMessages.length,
              itemBuilder: (context, index) {
                final msg = _controller.chatMessages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(msg.isUser ? "You" : "Iris", 
                        style: TextStyle(color: msg.isUser ? Colors.white38 : colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: msg.isUser ? colorScheme.primary.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: MarkdownBody(
                          data: msg.text ?? "",
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.6,
                              shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                            ),
                            code: TextStyle(
                              backgroundColor: Colors.black.withOpacity(0.3),
                              color: Colors.amberAccent,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicBackground() {
    return SizedBox.expand(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1000),
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: _buildCurrentBackground(),
      ),
    );
  }

  Widget _buildCurrentBackground() {
    if (_controller.assistantMode == MascotAssistantMode.chat) {
      return SizedBox.expand(
        key: const ValueKey('video_bg'),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _talkingController.value.size.width,
            height: _talkingController.value.size.height,
            child: VideoPlayer(_talkingController),
          ),
        ),
      );
    } else {
      return Image.asset(
        "assets/img/Iris_Hi.png",
        key: const ValueKey('image_bg'),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
  }
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final double opacity = ((_controller.value * 3 - index).remainder(3) / 3).clamp(0.2, 1.0);
            return Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(opacity),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.white.withOpacity(opacity * 0.5), blurRadius: 4, spreadRadius: 1)
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
