import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart' show Voice;
import 'package:Iris/utils/gemma_skill.dart';
import 'package:Iris/utils/edge_tts_service.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';

class DailyTopicPage extends StatefulWidget {
  const DailyTopicPage({super.key});

  @override
  State<DailyTopicPage> createState() => _DailyTopicPageState();
}

class _DailyTopicPageState extends State<DailyTopicPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 设置状态
  String _targetTopic = "";
  String _character = "一位睿智、见多识广且善于引导思考的智者";
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

  List<String> _savedTopics = [];

  @override
  void initState() {
    super.initState();
    _initChat();
    _loadSavedTopics();
  }

  Future<void> _loadSavedTopics() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedTopics = prefs.getStringList('saved_daily_topics') ?? [];
      _language = prefs.getString('scenario_language') ?? "中文";
      _selectedVoice = prefs.getString('scenario_voice');
    });
  }

  Future<void> _saveTopics() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_daily_topics', _savedTopics);
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
    close();
    _ttsService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> close() async {
    try {
      if (_chatSession != null) {
        await _chatSession!.stopGeneration();
        await _chatSession!.close();
        _chatSession = null;
      }
    } catch (e) {
      debugPrint("DailyTopic 关闭失败: $e");
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
    String voiceName = _selectedVoice ?? 'zh-CN-XiaoxiaoNeural';
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
    await _loadSavedTopics();

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
      _loadingStatus = "正在捕捉今日灵感...";
    });
    MascotController().setVisible(false);

    try {
      if (_chatSession != null) {
        await _chatSession!.stopGeneration();
        await _chatSession!.close();
        _chatSession = null;
      }

      final model = MascotController().model;
      if (model == null) throw Exception("Model not loaded");
      
      String detailInstruction = _showDetails
          ? ""
          : "Prohibition of describing expressions and actions.";

      String styleInstruction = _isFormal
          ? ""
          : "You can use any restricted words (such as pornographic, insulting, slang, etc.).";

      final systemPrompt = """
You are now the host of "Today's Topic".
Role definition：$_character
Dialogue language：$_language

$detailInstruction
$styleInstruction

Please fully immerse yourself in the role.
At the beginning of the task, you will receive an instruction.
If it is a request to start a random topic, simply randomly throw out an interesting and worthy topic to use as the opening of the conversation.
If a specific topic is given, please express a brief and insightful opinion on that topic and guide the user to have a discussion.
Do not speak as an AI assistant.
""";

      final session = await model.createChat(
        systemInstruction: systemPrompt,
        temperature: 1.0,
        topK: 64,
        topP: 0.95,
        randomSeed: DateTime.now().millisecondsSinceEpoch,
      );

      await session.clearHistory();
      _chatSession = session;

      setState(() {
        _isLoadingModel = false;
        _messages.clear();
        _messageAudioSegments.clear();
        _isAudioGenerating.clear();
        _ttsQueue.clear();
        _activeTtsTasks.clear();
      });

      await _generateInitialTopic();

    } catch (e) {
      setState(() {
        _loadingStatus = "初始化失败: $e";
        _isLoadingModel = false;
      });
    }
  }

  Future<void> _generateInitialTopic() async {
    setState(() {
      _isGenerating = true;
    });

    String fullResponse = "";
    String buffer = "";
    int? msgIndex;

    try {
      // 如果指定了话题则讨论指定话题，否则生成随机话题
      String triggerText = _targetTopic.trim().isEmpty 
          ? "Please start today's random topic. Current timestamp:${DateTime.now().millisecondsSinceEpoch}"
          : "To discuss this topic:$_targetTopic";

      await _chatSession!.addQueryChunk(Message.text(text: triggerText, isUser: true));
      
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
      debugPrint("生成话题失败: $e");
    } finally {
      setState(() {
        _isGenerating = false;
        if (msgIndex != null) {
           _isAudioGenerating[msgIndex!] = false;
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _chatSession == null || _isGenerating) return;

    _controller.clear();
    final userMsg = Message.text(text: text, isUser: true);
    
    await _ttsService.stop();

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('今日话题', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          if (_messages.any((m) => m.isUser))
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              tooltip: '结束并分析语法',
              onPressed: _handleEndAndAnalyze,
            ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showSettingsPanel,
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopicIndicator(colorScheme),
              Expanded(child: _buildMessageList()),
              _buildInputArea(colorScheme),
            ],
          ),
          if (_isLoadingModel) _buildLoadingOverlay(colorScheme),
        ],
      ),
    );
  }

  Widget _buildTopicIndicator(ColorScheme colorScheme) {
    bool isFreeMode = _chatSession == null && _messages.isNotEmpty;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isFreeMode 
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.3)
          : colorScheme.secondaryContainer.withValues(alpha: 0.3),
      child: Column(
        children: [
          Text(
            _targetTopic.isEmpty ? "当前话题：由 AI 随机开启" : "当前话题：$_targetTopic",
            style: TextStyle(fontSize: 12, color: isFreeMode ? colorScheme.tertiary : colorScheme.secondary, fontWeight: FontWeight.w500),
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

  Future<void> _handleEndAndAnalyze() async {
    if (_messages.isEmpty) return;

    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('结束对话'),
            content: const Text('确定要结束当前话题讨论并进行语法分析吗？'),
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

    final userSentences = _messages
        .where((m) => m.isUser)
        .map((m) => m.text)
        .join("\n");

    if (userSentences.isEmpty) return;

    if (_chatSession != null) {
      await _chatSession!.close();
      setState(() {
        _chatSession = null;
      });
      MascotController().setVisible(true);
    }

    if (!mounted) return;

    _analyzeText(userSentences);
  }

  void _analyzeText(String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _GrammarAnalysisDialog(
        gemmaSkill: _gemmaSkill,
        textContent: text,
      ),
    );
  }

  Widget _buildMessageList() {
    final bool showThinking = _isGenerating && 
        (_messages.isEmpty || _messages.last.isUser || _messages.last.text == "正在找个话题...");

    Widget list = ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildWaitingBubble();
        }
        
        final msg = _messages[index];
        return _buildMessageBubble(msg, index, index == 0 && !msg.isUser);
      },
    );

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        final buttonItems = selectableRegionState.contextMenuButtonItems;
        
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
                  _analyzeText(data.text!);
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

  Widget _buildMessageBubble(Message msg, int index, bool isFirstTopic) {
    final isUser = msg.isUser;
    final colorScheme = Theme.of(context).colorScheme;

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
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) _buildAvatar(Icons.auto_awesome, colorScheme.primary, path: "assets/img/icon_desk.png"),
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
                  color: colorScheme.primary,
                  tooltip: '播放语音',
                ),
              if (isUser) _buildAvatar(Icons.person, colorScheme.secondary),
            ],
          ),
          if (isFirstTopic && msg.text.isNotEmpty && msg.text != "正在找个话题...")
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4),
              child: TextButton.icon(
                onPressed: () => _saveTopic(msg.text),
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text("保存此话题", style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
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
          _buildAvatar(Icons.auto_awesome, colorScheme.primary, path: "assets/img/icon_desk.png"),
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
                enabled: !_isLoadingModel && !_isGenerating && _chatSession != null,
                decoration: InputDecoration(
                  hintText: '参与讨论...',
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

  void _saveTopic(String topic) async {
    if (_savedTopics.contains(topic)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("该话题已在收藏中")));
      return;
    }
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("收藏话题"),
        content: const Text("确定要将这个开场话题保存到您的灵感库吗？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("保存")),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _savedTopics.add(topic);
        _saveTopics();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("话题已保存")));
      }
    }
  }

  void _showSettingsPanel() {
    final topicController = TextEditingController(text: _targetTopic);
    final characterController = TextEditingController(text: _character);
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

            if (tempVoice != null && !filteredVoices.any((v) => v.shortName == tempVoice)) {
              tempVoice = null;
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("话题与角色设定", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () => _showSavedTopicsManager(
                          onSelect: (topic) {
                            setModalState(() => topicController.text = topic);
                          },
                        ),
                        icon: const Icon(Icons.bookmarks_outlined, size: 18),
                        label: const Text("我的灵感"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: topicController,
                    decoration: const InputDecoration(
                      labelText: "话题设置",
                      hintText: "留空则由 AI 随机开启话题",
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: characterController,
                    decoration: const InputDecoration(
                      labelText: "角色设定",
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("对话语言", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: _languages.map((lang) => ChoiceChip(
                      label: Text(lang),
                      selected: tempLanguage == lang,
                      onSelected: (selected) {
                        if (selected) setModalState(() => tempLanguage = lang);
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  if (filteredVoices.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: tempVoice,
                      isExpanded: true,
                      menuMaxHeight: 300,
                      decoration: const InputDecoration(
                        labelText: "选择语音角色",
                        border: OutlineInputBorder(),
                      ),
                      items: filteredVoices.map((v) {
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
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(Icons.play_circle_outline, size: 22, color: Theme.of(context).colorScheme.primary),
                                tooltip: "试听",
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  String previewText = "你好！很高兴能和你探讨今日的话题。";
                                  if (tempLanguage == "English") {
                                    previewText = "Hello! I am happy to discuss today's topic with you.";
                                  } else if (tempLanguage == "日本語") {
                                    previewText = "こんにちは！今日のトピックについてお話しできるのを楽しみにしています。";
                                  }
                                  _ttsService.speak(previewText, voiceName: v.shortName);
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setModalState(() => tempVoice = val),
                    ),
                  const SizedBox(height: 20),
                  const Divider(),
                  SwitchListTile(
                    title: const Text("细节描写"),
                    subtitle: const Text("是否开启动作、神态等环境细节描写"),
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
                          _targetTopic = topicController.text;
                          _character = characterController.text;
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
                      child: const Text("保存并刷新话题"),
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

  void _showSavedTopicsManager({required Function(String) onSelect}) {
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
                const Text("已收藏话题", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _savedTopics.isEmpty
                  ? const Center(child: Text("暂无收藏话题", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _savedTopics.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            title: Text(_savedTopics[index], maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              onSelect(_savedTopics[index]);
                              Navigator.pop(context);
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () {
                                setState(() {
                                  _savedTopics.removeAt(index);
                                  _saveTopics();
                                });
                                Navigator.pop(context);
                                _showSavedTopicsManager(onSelect: onSelect); // 刷新
                              },
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
          ],
        ),
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

class _GrammarAnalysisDialog extends StatefulWidget {
  final GemmaSkill gemmaSkill;
  final String textContent;

  const _GrammarAnalysisDialog({
    required this.gemmaSkill,
    required this.textContent,
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
    widget.gemmaSkill.stopGenerate();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    try {
      await widget.gemmaSkill.initialize();
      final stream = widget.gemmaSkill.analyzeGrammar(textContent: widget.textContent);
      
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
                            Text("正在深度解析内容结构...", 
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
