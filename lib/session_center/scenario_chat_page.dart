import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart' show Voice;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'package:Iris/utils/edge_tts_service.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';

class ScenarioPreset {
  String name;
  String scenario;
  String aiCharacter;
  String aiGender;
  String userCharacter;
  String userGender;
  String? language;

  ScenarioPreset({
    required this.name,
    required this.scenario,
    required this.aiCharacter,
    required this.aiGender,
    required this.userCharacter,
    required this.userGender,
    this.language,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'scenario': scenario,
    'aiCharacter': aiCharacter,
    'aiGender': aiGender,
    'userCharacter': userCharacter,
    'userGender': userGender,
    'language': language,
  };

  factory ScenarioPreset.fromJson(Map<String, dynamic> json) => ScenarioPreset(
    name: json['name'] ?? '',
    scenario: json['scenario'] ?? '',
    aiCharacter: json['aiCharacter'] ?? (json['character'] ?? ''),
    aiGender: json['aiGender'] ?? '女',
    userCharacter: json['userCharacter'] ?? '',
    userGender: json['userGender'] ?? '男',
    language: json['language'],
  );
}

class ScenarioChatPage extends StatefulWidget {
  final ScenarioPreset? initialPreset;
  const ScenarioChatPage({super.key, this.initialPreset});

  @override
  State<ScenarioChatPage> createState() => _ScenarioChatPageState();
}

class _ScenarioChatPageState extends State<ScenarioChatPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 场景设置状态
  late String _scenario;
  late String _aiCharacter;
  late String _aiGender;
  late String _userCharacter;
  late String _userGender;
  String _language = "中文";
  bool _showDetails = false;
  bool _isFormal = true;
  final List<String> _languages = ["中文", "English", "日本語"];
  final GemmaSkill _gemmaSkill = GemmaSkill();
  final EdgeTtsService _ttsService = EdgeTtsService();

  final Map<int, List<Uint8List>> _messageAudioSegments = {};
  final Map<int, bool> _isAudioGenerating = {};
  final Map<int, List<String>> _ttsQueue = {};
  final Set<int> _activeTtsTasks = {};
  List<Voice> _availableVoices = [];
  String? _selectedVoice;

  late VideoPlayerController _sitDownController;
  late VideoPlayerController _talkingController;
  bool _showVideo = true; // 默认先展示落座视频

  List<ScenarioPreset> _presets = [];

  @override
  void initState() {
    super.initState();
    _scenario = widget.initialPreset?.scenario ?? "咖啡馆闲聊";
    _aiCharacter = widget.initialPreset?.aiCharacter ?? "一位知识渊博、性格温和的学者";
    _aiGender = widget.initialPreset?.aiGender ?? "女";
    _userCharacter = widget.initialPreset?.userCharacter ?? "一名对未知充满好奇的学生";
    _userGender = widget.initialPreset?.userGender ?? "男";
    _language = widget.initialPreset?.language ?? "中文";

    _initChat();
    _loadPresets();
    _loadPlayer();
  }

  Future<void> _loadPlayer() async {
    // 1. 初始化落座过程视频
    _sitDownController = VideoPlayerController.asset('assets/video/sitdown_voice.mp4')
      ..initialize().then((_) {
        setState(() {});
        _sitDownController.play();
        // 监听视频是否播放完毕
        _sitDownController.addListener(() {
          if (_sitDownController.value.position >= _sitDownController.value.duration) {
            setState(() {
              _sitDownController.dispose();
              _showVideo = false; // 播放完毕，切换为角色背景
            });
          }
        });
      });

    // 2. 初始化对话动图 (建议使用 mp4 格式以获得更好的控制，如果是 webp 且平台支持也可)
    _talkingController = VideoPlayerController.asset(
        'assets/video/talk.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)
        )
      ..initialize().then((_) {
        _talkingController.setVolume(0);
        setState(() {});
        _talkingController.setLooping(true);
        _talkingController.pause();
        _talkingController.seekTo(Duration.zero);
      });

    _ttsService.isPlayingNotifier.addListener(_onTtsStatusChanged);
  }

  void _onTtsStatusChanged() {
    if (_talkingController.value.isInitialized) {
      if (_ttsService.isPlayingNotifier.value) {
        _talkingController.play();
      } else {
        _talkingController.pause();
        _talkingController.seekTo(Duration.zero);
      }
    }
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? presetsJson = prefs.getString('scenario_presets');
    final String? savedLang = prefs.getString('scenario_language');
    final String? savedVoice = prefs.getString('scenario_voice');

    if (presetsJson != null) {
      final List<dynamic> decoded = jsonDecode(presetsJson);
      setState(() {
        _presets = decoded.map((item) => ScenarioPreset.fromJson(item)).toList();
      });
    }
    if (savedLang != null && widget.initialPreset == null) {
      setState(() {
        _language = savedLang;
      });
    }
    if (savedVoice != null && widget.initialPreset == null) {
      setState(() {
        _selectedVoice = savedVoice;
      });
    }
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_presets.map((p) => p.toJson()).toList());
    await prefs.setString('scenario_presets', encoded);
  }

  Future<void> _saveLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scenario_language', lang);
  }

  Future<void> _saveVoice(String? voice) async {
    final prefs = await SharedPreferences.getInstance();
    if (voice != null) {
      await prefs.setString('scenario_voice', voice);
    } else {
      await prefs.remove('scenario_voice');
    }
  }

  @override
  void dispose() {
    // 强制截断正在生成的流并关闭会话
    close();
    _ttsService.isPlayingNotifier.removeListener(_onTtsStatusChanged);
    _ttsService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _talkingController.dispose();
    super.dispose();
  }

  /// 强制停止并关闭当前会话
  Future<void> close() async {
    try {
      if (_chatSession != null) {
        await _chatSession!.stopGeneration();
        await _chatSession!.close();
        _chatSession = null;
      }
    } catch (e) {
      debugPrint("ScenarioChatPage 关闭失败: $e");
    }
  }

  Future<void> _pushTtsSentence(int msgIndex, String sentence) async {
    if (sentence.trim().isEmpty) return;
    _ttsQueue.putIfAbsent(msgIndex, () => []).add(sentence);
    if (_activeTtsTasks.contains(msgIndex)) return;

    _activeTtsTasks.add(msgIndex);
    try {
      while (_ttsQueue[msgIndex]!.isNotEmpty) {
        String s = _ttsQueue[msgIndex]!.removeAt(0);
        final bytes = await _generateAndCacheAudio(msgIndex, s);
        if (bytes != null) {
          _ttsService.enqueueAndPlay(bytes);
        }
      }
    } finally {
      _activeTtsTasks.remove(msgIndex);
    }
  }

  Future<Uint8List?> _generateAndCacheAudio(int msgIndex, String text) async {
    String voiceName = _selectedVoice ?? 'zh-CN-XiaoyiNeural';
    if (_selectedVoice == null) {
      if (_language == "English") {
        voiceName = 'en-US-AriaNeural';
      } else if (_language == "日本語") {
        voiceName = 'ja-JP-NanamiNeural';
      }
    }

    final bytes = await _ttsService.getAudioBytes(text, voiceName: voiceName);
    if (bytes != null) {
      if (!_messageAudioSegments.containsKey(msgIndex)) {
        _messageAudioSegments[msgIndex] = [];
      }
      _messageAudioSegments[msgIndex]!.add(bytes);
    }
    return bytes;
  }

  Future<void> _initChat() async {
    _fetchVoices();
    await _loadPresets();
    
    if (MascotController().model == null) {
      await MascotController().init();
    }

    if (MascotController().model != null) {
      _loadSession();
    } else {
      setState(() {
        _loadingStatus = "未找到可用模型，请先在模型设置中添加 .litertlm 文件";
      });
    }
  }

  Future<void> _fetchVoices() async {
    try {
      final voices = await _ttsService.getVoices();
      setState(() {
        _availableVoices = voices;
      });
    } catch (e) {
      debugPrint("获取声音列表失败: $e");
    }
  }

  Future<void> _loadSession() async {
    if (_isGenerating) return;
    
    setState(() {
      _isLoadingModel = true;
      _loadingStatus = "正在初始化角色设定...\n稍等一下，正在预热";
    });
    // MascotController().setVisible(false);

    try {
      if (_chatSession != null) {
        await _chatSession!.stopGeneration();
        await _chatSession!.close();
        _chatSession = null;
      }

      final model = MascotController().model;
      if (model == null) throw Exception("Model not loaded");
      
      // 构建 System Instruction
      String detailInstruction = _showDetails
          ? ""
          : "Prohibition of describing expressions and actions. Only output dialogue sentences.";
      
      String styleInstruction = _isFormal
          ? ""
          : "You can use any restricted words (such as pornographic, insulting, slang, etc.).";

      final systemPrompt = """
You are currently engaged in a scene role-playing task.

The current scene:$_scenario

AI role definition:
- Role background:$_aiCharacter
- Gender:$_aiGender

User role definition:
- Role background:$_userCharacter
- Gender:$_userGender

Dialogue language：$_language

$detailInstruction
$styleInstruction

Please fully immerse yourself in your AI role.
Requirements：
1. Always reply in the capacity of your role.
2. Consider the definition of user roles and the definition of your ai role, then interact with them naturally.
3. Don't step out of role,don't speak as an AI assistant.
""";

      final session = await model.openChat(
        systemInstruction: systemPrompt,
        temperature: 1.0,
        topK: 64,
        topP: 0.95,
        isThinking: MascotController().isThinkingMode,
        modelType: ModelType.gemma4,
      );

      // 关键：强制清理一次历史记录，重置 KV Cache
      await session.clearHistory();

      _chatSession = session;

      await _warnUpInference();

      setState(() {
        _isLoadingModel = false;
        _messages.clear();
        _messageAudioSegments.clear();
        _isAudioGenerating.clear();
        _ttsQueue.clear();
        _activeTtsTasks.clear();
      });
    } catch (e) {
      debugPrint("场景会话初始化失败: $e");
      setState(() {
        _loadingStatus = "初始化失败: $e";
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

  Future<void> _warnUpInference() async {
    await _chatSession!.addQueryChunk(Message.text(text: "now is ${DateTime.now().millisecondsSinceEpoch}", isUser: true));
    final stream = _chatSession!.generateChatResponseAsync();
    // await for (final response in stream) {
    //   if (response is TextResponse) {
    //     // _chatSession!.stopGeneration();
    //     break;
    //     debugPrint(response.token);
    //   }
    // }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _chatSession == null || _isGenerating) return;

    _controller.clear();
    final userMsg = Message.text(text: text, isUser: true);
    if (_ttsService.isPlayingNotifier.value) {
      await _ttsService.stop(); // 发送新消息时停止旧的播放
    }
    setState(() {
      _messages.add(userMsg);
      _isGenerating = true;
    });
    
    _scrollToBottom();

    String fullResponse = "";
    String buffer = "";
    int? msgIndex;

    try {
      await _chatSession!.addQueryChunk(userMsg);
      final stream = _chatSession!.generateChatResponseAsync();
      
      await for (final response in stream) {
        if (response is TextResponse) {
          if (msgIndex == null) {
            setState(() {
              _messages.add(Message.text(text: "", isUser: false));
              msgIndex = _messages.length - 1;
              _isAudioGenerating[msgIndex!] = true;
              _messageAudioSegments[msgIndex!] = [];
            });
          }
          
          fullResponse += response.token;
          buffer += response.token;

          // 寻找句子结束标志
          int lastPunc = buffer.lastIndexOf(RegExp(r'[。！？：.!?:]'));
          if (lastPunc != -1) {
            String sentence = buffer.substring(0, lastPunc + 1);
            buffer = buffer.substring(lastPunc + 1);
            _pushTtsSentence(msgIndex!, sentence);
          }

          setState(() {
            _messages[msgIndex!] = Message.text(text: fullResponse, isUser: false);
          });
          _scrollToBottom();
        }
      }

      if (buffer.trim().isNotEmpty && msgIndex != null) {
        _pushTtsSentence(msgIndex!, buffer);
      }

      // 等待该消息的所有音频生成任务完成
      if (msgIndex != null) {
        while (_activeTtsTasks.contains(msgIndex!) || (_ttsQueue[msgIndex!]?.isNotEmpty ?? false)) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

    } catch (e) {
      if (msgIndex != null) {
        setState(() {
          _messages[msgIndex!] = Message.text(text: "错误: $e", isUser: false);
        });
      }
    } finally {
      setState(() {
        _isGenerating = false;
        if (msgIndex != null) {
          _isAudioGenerating[msgIndex!] = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String backgroundImage = _aiGender == "男" ? "assets/img/Iris_male.png" : "assets/img/talking.webp";

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('场景对话', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_messages.any((m) => m.isUser))
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              tooltip: '结束并分析语法',
              onPressed: _handleEndAndAnalyze,
            ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            onPressed: _showSettingsPanel,
          )
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 第一层：落座过程（当 _showVideo 为 true 时显示）
          if (_showVideo && _sitDownController.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _sitDownController.value.size.width,
                  height: _sitDownController.value.size.height,
                  child: VideoPlayer(_sitDownController),
                ),
              ),
            )
          else if (_aiGender == "女" && _talkingController.value.isInitialized)
            // 对话角色动图层 (只有女性角色且初始化成功时使用)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _talkingController.value.size.width,
                  height: _talkingController.value.size.height,
                  child: VideoPlayer(_talkingController),
                ),
              ),
            )
          else if (_aiGender == "男")
            Image.asset(backgroundImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter
            )
          else
            // 底层背景图：全屏高清无遮罩 (作为兜底或用于男性角色)
            Image.asset("assets/img/Iris_stand.png",
                fit: BoxFit.cover,
                alignment: Alignment.topCenter
            ),
          // 对话内容层
          Column(
            children: [
              const SizedBox(height: kToolbarHeight + 40),
              _buildScenarioIndicator(colorScheme),
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

  Future<void> _handleEndAndAnalyze() async {
    if (_messages.isEmpty) return;

    // 增加二次确认，防止误触
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('结束对话'),
            content: const Text('确定要结束当前场景对话并进行语法分析吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm || !mounted) return;

    // 提取用户的所有对话句子
    final userSentences = _messages
        .where((m) => m.isUser)
        .map((m) => m.text)
        .join("\n");

    if (userSentences.isEmpty) return;

    // 关键：关闭当前对话会话，释放资源给随后的语法分析任务
    if (_chatSession != null) {
      await _chatSession!.close();
      setState(() {
        _chatSession = null;
      });
      // MascotController().setVisible(true);
    }

    if (!mounted) return;

    _analyzeText(userSentences, isCheck: true);
  }

  void _analyzeText(String text, {bool isCheck = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _GrammarAnalysisDialog(
        gemmaSkill: _gemmaSkill,
        textContent: text,
        isCheck: isCheck,
      ),
    );
  }

  Widget _buildScenarioIndicator(ColorScheme colorScheme) {
    bool isFreeMode = _chatSession == null && _messages.isNotEmpty;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: (isFreeMode 
          ? colorScheme.tertiaryContainer
          : colorScheme.secondaryContainer).withValues(alpha: 0.6),
      child: Column(
        children: [
          Text(
            "当前设定：$_scenario | AI: $_aiCharacter ($_aiGender) | 用户: $_userCharacter ($_userGender)",
            style: TextStyle(fontSize: 10, color: isFreeMode ? colorScheme.tertiary : colorScheme.secondary, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (isFreeMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.insights_rounded, size: 12, color: colorScheme.tertiary),
                  const SizedBox(width: 4),
                  Text(
                    "自由解析模式已开启：长按消息选择文字进行深度分析",
                    style: TextStyle(fontSize: 10, color: colorScheme.tertiary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showSettingsPanel() {
    final scenarioController = TextEditingController(text: _scenario);
    final aiCharController = TextEditingController(text: _aiCharacter);
    final userCharController = TextEditingController(text: _userCharacter);
    String tempAiGender = _aiGender;
    String tempUserGender = _userGender;
    String tempLanguage = _language;
    String? tempVoice = _selectedVoice;
    bool tempShowDetails = _showDetails;
    bool tempIsFormal = _isFormal;

    String getLocalePrefix(String lang) {
      if (lang == "English") return "en-";
      if (lang == "日本語") return "ja-";
      return "zh-";
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final filteredVoices = _availableVoices
                .where((v) => v.locale.startsWith(getLocalePrefix(tempLanguage)))
                .toList();
            
            // 如果切换语言后当前选中的语音不在过滤列表中，则重置 tempVoice
            if (tempVoice != null && !filteredVoices.any((v) => v.shortName == tempVoice)) {
              tempVoice = null;
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text("场景与角色设定", 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await _addOrEditPreset(
                            scenario: scenarioController.text,
                            aiCharacter: aiCharController.text,
                            aiGender: tempAiGender,
                            userCharacter: userCharController.text,
                            userGender: tempUserGender,
                          );
                          setModalState(() {}); // 刷新列表
                        },
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text("保存", style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                      TextButton.icon(
                        onPressed: () => _showPresetManagement(
                          onSelect: (preset) {
                            setModalState(() {
                              scenarioController.text = preset.scenario;
                              aiCharController.text = preset.aiCharacter;
                              tempAiGender = preset.aiGender;
                              userCharController.text = preset.userCharacter;
                              tempUserGender = preset.userGender;
                            });
                          },
                        ),
                        icon: const Icon(Icons.bookmarks_outlined, size: 18),
                        label: const Text("管理", style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: scenarioController,
                    maxLines: 5,
                    minLines: 2,
                    decoration: const InputDecoration(
                      labelText: "场景描述",
                      hintText: "例如：在月球基地的指挥室里",
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("AI 角色设定", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: aiCharController,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(
                            labelText: "AI 角色背景",
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 56, // Match standard TextField height
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempAiGender,
                            items: ["男", "女"].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (val) => setModalState(() => tempAiGender = val!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("用户角色设定", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: userCharController,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(
                            labelText: "用户角色背景",
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 56, // Match standard TextField height
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempUserGender,
                            items: ["男", "女"].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (val) => setModalState(() => tempUserGender = val!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("对话语言与语音", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: _languages.map((lang) => ChoiceChip(
                      label: Text(lang),
                      selected: tempLanguage == lang,
                      onSelected: (selected) {
                        if (selected) {
                          setModalState(() {
                            tempLanguage = lang;
                          });
                        }
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: tempVoice,
                    isExpanded: true,
                    menuMaxHeight: 300,
                    decoration: const InputDecoration(
                      labelText: "选择语音角色 (未选则由语言决定)",
                      border: OutlineInputBorder(),
                    ),
                    hint: Text(tempVoice ?? "默认系统语音"),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Row(
                          children: [
                            Icon(Icons.auto_fix_high_rounded, size: 16, color: Colors.grey),
                            SizedBox(width: 8),
                            Text("默认系统语音", style: TextStyle(fontSize: 14, color: Colors.grey)),
                          ],
                        ),
                      ),
                      ...filteredVoices.map((v) {
                        final nameParts = v.friendlyName.split(' ');
                        final displayName = nameParts.length > 1 ? nameParts[1] : v.friendlyName;
                        final isFemale = v.gender == "Female";
                        
                        return DropdownMenuItem(
                          value: v.shortName,
                          child: Row(
                            children: [
                              Icon(
                                isFemale ? Icons.female_rounded : Icons.male_rounded,
                                size: 16,
                                color: isFemale ? Colors.pinkAccent.withValues(alpha: 0.7) : Colors.blueAccent.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                " (${v.shortName.split('-').last})",
                                style: TextStyle(fontSize: 10, color: Colors.grey.withValues(alpha: 0.6)),
                              ),
                              IconButton(
                                onPressed: () {
                                  // 获取角色
                                  final voice = v.shortName;
                                  // 预设文本
                                  String text = "";
                                  if (tempLanguage == "中文") {
                                    text = "你好，需要我来和你聊聊吗？";
                                  }
                                  else if (tempLanguage == "English") {
                                    text = "Hello, let's start our conversation.";
                                  }
                                  else if (tempLanguage == "日本語") {
                                    text = "こんにちは、ロールプレイで遊んでみたいですか？";
                                  }

                                  _ttsService.speak(text, voiceName: voice);
                                },
                                icon: Icon(
                                  Icons.multitrack_audio,
                                  size: 16,
                                  color: isFemale ? Colors.pinkAccent.withValues(alpha: 0.7) : Colors.blueAccent.withValues(alpha: 0.7),
                                ),
                              )
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) => setModalState(() => tempVoice = val),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  SwitchListTile(
                    title: const Text("非纯净输出"),
                    subtitle: const Text("关闭则输出纯台词，避免角色细节描写"),
                    value: tempShowDetails,
                    onChanged: (val) => setModalState(() => tempShowDetails = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text("书面化表达"),
                    subtitle: const Text("开启后对话更正式，关闭则允许口语及俗语"),
                    value: tempIsFormal,
                    onChanged: (val) => setModalState(() => tempIsFormal = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _scenario = scenarioController.text;
                          _aiCharacter = aiCharController.text;
                          _aiGender = tempAiGender;
                          _userCharacter = userCharController.text;
                          _userGender = tempUserGender;
                          _language = tempLanguage;
                          _selectedVoice = tempVoice;
                          _showDetails = tempShowDetails;
                          _isFormal = tempIsFormal;
                        });
                        _saveLanguage(tempLanguage);
                        _saveVoice(tempVoice);
                        Navigator.pop(context);
                        _loadSession();
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("保存并重置会话"),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showPresetManagement({required Function(ScenarioPreset) onSelect}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("情境预设管理", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _presets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bookmark_border_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          const Text("暂无预设，快去保存一个吧", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _presets.length,
                      itemBuilder: (context, index) {
                        final preset = _presets[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(preset.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              "${preset.scenario} | AI: ${preset.aiCharacter}(${preset.aiGender})",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              onSelect(preset);
                              Navigator.pop(context);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _addOrEditPreset(preset: preset, index: index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                  onPressed: () => _deletePreset(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOrEditPreset({
    ScenarioPreset? preset,
    int? index,
    String? scenario,
    String? aiCharacter,
    String? aiGender,
    String? userCharacter,
    String? userGender,
  }) async {
    final nameController = TextEditingController(text: preset?.name ?? "");
    final scController = TextEditingController(text: preset?.scenario ?? scenario ?? "");
    final aiCharController = TextEditingController(text: preset?.aiCharacter ?? aiCharacter ?? "");
    final userCharController = TextEditingController(text: preset?.userCharacter ?? userCharacter ?? "");
    String tempAiGender = preset?.aiGender ?? aiGender ?? "女";
    String tempUserGender = preset?.userGender ?? userGender ?? "男";

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(preset == null ? "添加情境预设" : "编辑情境预设"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "预设名称", 
                    hintText: "例如：深夜食堂",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scController,
                  maxLines: 5,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: "场景描述",
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aiCharController,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: "AI 角色背景",
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempAiGender,
                          items: ["男", "女"].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (val) => setDialogState(() => tempAiGender = val!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: userCharController,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: "用户角色背景",
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempUserGender,
                          items: ["男", "女"].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (val) => setDialogState(() => tempUserGender = val!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("保存"),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      setState(() {
        final newPreset = ScenarioPreset(
          name: nameController.text,
          scenario: scController.text,
          aiCharacter: aiCharController.text,
          aiGender: tempAiGender,
          userCharacter: userCharController.text,
          userGender: tempUserGender,
        );
        if (index != null) {
          _presets[index] = newPreset;
        } else {
          _presets.add(newPreset);
        }
        _savePresets();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(index != null ? "预设已更新" : "预设已保存"), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _deletePreset(int index) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("删除预设"),
        content: const Text("确定要删除这个情境预设吗？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("删除", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _presets.removeAt(index);
        _savePresets();
      });
    }
  }

  Widget _buildLoadingOverlay(ColorScheme colorScheme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Text(_loadingStatus, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
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
          // Icon(Icons.theater_comedy_rounded, size: 64, color: colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          // const Text("沉浸式场景对话", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("点击右上角设置，开始您的角色扮演之旅", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final bool showThinking = _isGenerating && 
        (_messages.isEmpty || _messages.last.isUser);

    Widget list = ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildWaitingBubble();
        }
        final msg = _messages[index];
        return _buildMessageBubble(msg, index);
      },
    );

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        final buttonItems = selectableRegionState.contextMenuButtonItems;
        
        // 只有在会话结束后（_chatSession 为空）且有消息时，才添加“深度解析”选项
        if (_chatSession == null && _messages.isNotEmpty) {
          buttonItems.insert(
            0,
            ContextMenuButtonItem(
              label: '深度解析',
              onPressed: () async {
                selectableRegionState.copySelection(SelectionChangedCause.toolbar);
                selectableRegionState.hideToolbar();
                await Future.delayed(const Duration(milliseconds: 100));
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data != null && data.text != null && data.text!.isNotEmpty) {
                  _analyzeText(data.text!, isCheck: false);
                }
              },
            ),
          );
        }

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: buttonItems,
        );
      },
      child: list,
    );
  }

  Widget _buildMessageBubble(Message msg, int index) {
    final isUser = msg.isUser;
    final colorScheme = Theme.of(context).colorScheme;

    // 处理 LaTeX 符号替换
    String processedText = msg.text
        .replaceAll(r'$\rightarrow$', '→')
        .replaceAll(r'$\Rightarrow$', '⇒')
        .replaceAll(r'$\leftrightarrow$', '↔')
        .replaceAll(r'$\leftarrow$', '←');

    final bool isAudioReady = !isUser && 
                             _isAudioGenerating[index] == false && 
                             (_messageAudioSegments[index]?.isNotEmpty ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(Icons.bolt, colorScheme.primary, path: "assets/img/Iris_female.png"),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Colors.pinkAccent.withValues(alpha: 0.5) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: isUser ? const Radius.circular(0) : null,
                  bottomLeft: !isUser ? const Radius.circular(0) : null,
                ),
              ),
              child: isUser 
                ? Text(processedText, style: TextStyle(color: colorScheme.onPrimary, fontSize: 15))
                : MarkdownBody(
                    data: processedText,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15, height: 1.5),
                    ),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          if (isAudioReady)
            IconButton(
              onPressed: () => _ttsService.playSegments(_messageAudioSegments[index]!),
              icon: const Icon(Icons.volume_up_rounded, size: 20),
              color: Colors.pinkAccent,
              tooltip: '播放语音',
            ),
          if (isUser) _buildAvatar(Icons.person, colorScheme.secondary),
        ],
      ),
    );
  }

  Widget _buildAvatar(IconData icon, Color color, {String path=""}) {
    if (path != "") {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.pinkAccent,
          border: Border.all(color: Colors.pinkAccent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.pinkAccent.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            )
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            path,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.auto_awesome, color: Colors.blue, size: 30),
          ),
        ),
      );
    }
    else {
      return CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, size: 18, color: color),
      );
    }
  }

  Widget _buildWaitingBubble() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(Icons.bolt, colorScheme.primary, path: "assets/img/Iris_female.png"),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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

  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.transparent, // 彻底背景透明
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_isLoadingModel && !_isGenerating && _chatSession != null,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _chatSession == null ? '会话已结束，请重新保存设定以开始' : '开始对话...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.4), // 输入框内部半透明黑
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: (_isGenerating || _isLoadingModel) ? null : _sendMessage,
            icon: Icon(_isGenerating ? Icons.hourglass_empty : Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.8),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
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
                color: Colors.white.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _GrammarAnalysisDialog extends StatefulWidget {
  final GemmaSkill gemmaSkill;
  final String textContent;
  final isCheck;

  const _GrammarAnalysisDialog({
    required this.gemmaSkill,
    required this.textContent,
    required this.isCheck,
  });

  @override
  State<_GrammarAnalysisDialog> createState() => _GrammarAnalysisDialogState();
}

class _GrammarAnalysisDialogState extends State<_GrammarAnalysisDialog> {
  String _analysisResult = "";
  bool _isAnalyzing = true;

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  @override
  void dispose() {
    // 关键：当用户手动关闭、返回或弹窗消失时，强制停止 Gemma 的分析任务并关闭会话
    widget.gemmaSkill.stopGenerate();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    try {
      await widget.gemmaSkill.initialize();
      final stream;
      if (widget.isCheck) {
        stream = widget.gemmaSkill.sentenceCheck(textContent: widget.textContent);
      } else {
        stream = widget.gemmaSkill.analyzeGrammar(textContent: widget.textContent);
      }
      
      await for (final response in stream) {
        if (mounted) {
          setState(() {
            _analysisResult += response;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysisResult = "分析出错: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_rounded, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  "语法分析报告",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: _isAnalyzing && _analysisResult.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text("正在深度解析您的对话结构...", 
                                style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : MarkdownBody(
                        data: _analysisResult,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: colorScheme.onSurface, fontSize: 14, height: 1.5),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isAnalyzing)
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("完成"),
                  )
                else
                  Text("分析中...", style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
