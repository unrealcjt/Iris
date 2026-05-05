import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart' show Voice;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gemma_skill.dart';
import 'edge_tts_service.dart';

class ScenarioPreset {
  String name;
  String scenario;
  String character;

  ScenarioPreset({required this.name, required this.scenario, required this.character});

  Map<String, dynamic> toJson() => {
    'name': name,
    'scenario': scenario,
    'character': character,
  };

  factory ScenarioPreset.fromJson(Map<String, dynamic> json) => ScenarioPreset(
    name: json['name'],
    scenario: json['scenario'],
    character: json['character'],
  );
}

class ScenarioChatPage extends StatefulWidget {
  const ScenarioChatPage({super.key});

  @override
  State<ScenarioChatPage> createState() => _ScenarioChatPageState();
}

class _ScenarioChatPageState extends State<ScenarioChatPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<File> _availableModels = [];
  File? _currentModelFile;
  InferenceModel? _currentModel;
  InferenceChat? _chatSession;
  bool _isLoadingModel = false;
  String _loadingStatus = "";
  bool _isGenerating = false;

  // 场景设置状态
  String _scenario = "咖啡馆闲聊";
  String _character = "一位知识渊博、性格温和的学者";
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

  List<ScenarioPreset> _presets = [];

  @override
  void initState() {
    super.initState();
    _initChat();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? presetsJson = prefs.getString('scenario_presets');
    final String? savedLang = prefs.getString('scenario_language');
    if (presetsJson != null) {
      final List<dynamic> decoded = jsonDecode(presetsJson);
      setState(() {
        _presets = decoded.map((item) => ScenarioPreset.fromJson(item)).toList();
      });
    }
    if (savedLang != null) {
      setState(() {
        _language = savedLang;
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

  @override
  void dispose() {
    // 强制截断正在生成的流并关闭会话
    close();
    _ttsService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 强制停止并关闭所有会话，释放 Native 资源
  Future<void> close() async {
    try {
      if (_chatSession != null) {
        await _chatSession!.stopGeneration();
        await _chatSession!.close();
        _chatSession = null;
      }
      if (_currentModel != null) {
        await _currentModel!.close();
        _currentModel = null;
      }
    } catch (e) {
      debugPrint("GemmaSkill 关闭失败: $e");
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
      _loadingStatus = modelFile.path.toLowerCase().contains("e2b") ? "正在初始化角色设定...\n稍等一下，正在预热" : "正在初始化预热\n更大的模型会更耗时";
    });

    try {
      if (_chatSession != null) {
        await _chatSession!.stopGeneration();
        await _chatSession!.close();
        _chatSession = null;
      }

      await Future.delayed(const Duration(milliseconds: 300));

      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(modelFile.path)
          .install();
      
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
      );

      _currentModel = model;
      
      // 构建 System Instruction
      String detailInstruction = _showDetails
          ? ""
          : "请禁止任何动作描写、神态描写或环境描写，只允许输出角色对话的台词。";
      
      String styleInstruction = _isFormal
          ? ""
          : "允许使用口语化的非书面词汇，以及允许使用性暗示，色情，俚语等受限制的词汇语句，根据场景和角色设定决定是否使用，以完美融入角色为主。";

      final systemPrompt = """
你现在正在进行一个场景角色扮演任务。
当前场景：$_scenario
角色设定：$_character
对话语言：$_language

$detailInstruction
$styleInstruction

请完全沉浸在角色中，不要跳出角色，不要以AI助手的身份说话。
""";

      final session = await model.createChat(
        systemInstruction: systemPrompt,
        temperature: 0.95,
        topK: 30,
        topP: 0.9,
        randomSeed: DateTime.now().millisecondsSinceEpoch,
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
    await _chatSession!.addQueryChunk(Message.text(text: ".", isUser: true));
    final stream = _chatSession!.generateChatResponseAsync();
    await for (final response in stream) {
      if (response is TextResponse) {
        _chatSession!.stopGeneration();
        break;
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _chatSession == null || _isGenerating) return;

    _controller.clear();
    final userMsg = Message.text(text: text, isUser: true);
    
    await _ttsService.stop(); // 发送新消息时停止旧的播放

    setState(() {
      _messages.add(userMsg);
      _messages.add(Message.text(text: "", isUser: false));
      _isGenerating = true;
    });
    
    final msgIndex = _messages.length - 1;
    _isAudioGenerating[msgIndex] = true;
    _messageAudioSegments[msgIndex] = [];
    _scrollToBottom();

    try {
      await _chatSession!.addQueryChunk(userMsg);
      final stream = _chatSession!.generateChatResponseAsync();
      
      String fullResponse = "";
      String buffer = "";
      
      await for (final response in stream) {
        if (response is TextResponse) {
          fullResponse += response.token;
          buffer += response.token;

          // 寻找句子结束标志
          int lastPunc = buffer.lastIndexOf(RegExp(r'[。！？.!?]'));
          if (lastPunc != -1) {
            String sentence = buffer.substring(0, lastPunc + 1);
            buffer = buffer.substring(lastPunc + 1);
            _pushTtsSentence(msgIndex, sentence);
          }

          setState(() {
            _messages[msgIndex] = Message.text(text: fullResponse, isUser: false);
          });
          _scrollToBottom();
        }
      }

      if (buffer.trim().isNotEmpty) {
        _pushTtsSentence(msgIndex, buffer);
      }

      // 等待该消息的所有音频生成任务完成
      while (_activeTtsTasks.contains(msgIndex) || (_ttsQueue[msgIndex]?.isNotEmpty ?? false)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

    } catch (e) {
      setState(() {
        _messages[msgIndex] = Message.text(text: "错误: $e", isUser: false);
      });
    } finally {
      setState(() {
        _isGenerating = false;
        _isAudioGenerating[msgIndex] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('场景对话', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
    if (_messages.isEmpty || _currentModelFile == null) return;

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
    }

    if (!mounted) return;

    _analyzeText(userSentences);
  }

  void _analyzeText(String text) {
    if (_currentModelFile == null) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _GrammarAnalysisDialog(
        gemmaSkill: _gemmaSkill,
        modelFile: _currentModelFile!,
        textContent: text,
      ),
    );
  }

  Widget _buildScenarioIndicator(ColorScheme colorScheme) {
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
            "当前设定：$_scenario | $_character",
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

  void _showSettingsPanel() {
    final scenarioController = TextEditingController(text: _scenario);
    final characterController = TextEditingController(text: _character);
    String tempLanguage = _language;
    String? tempVoice = _selectedVoice;
    bool tempShowDetails = _showDetails;
    bool tempIsFormal = _isFormal;
    File? tempModelFile = _currentModelFile;

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("场景与角色设定", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () => _showPresetManagement(
                          onSelect: (preset) {
                            setModalState(() {
                              scenarioController.text = preset.scenario;
                              characterController.text = preset.character;
                            });
                          },
                        ),
                        icon: const Icon(Icons.bookmarks_outlined, size: 18),
                        label: const Text("情境管理"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<File>(
                    value: tempModelFile,
                    decoration: const InputDecoration(
                      labelText: "选择模型",
                      border: OutlineInputBorder(),
                    ),
                    items: _availableModels.map((file) => DropdownMenuItem(
                      value: file,
                      child: Text(p.basename(file.path), style: const TextStyle(fontSize: 14)),
                    )).toList(),
                    onChanged: (val) => setModalState(() => tempModelFile = val),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: scenarioController,
                    decoration: const InputDecoration(
                      labelText: "场景描述",
                      hintText: "例如：在月球基地的指挥室里",
                      suffixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: characterController,
                    decoration: const InputDecoration(
                      labelText: "角色设定",
                      hintText: "例如：一位严谨且略带幽默的基座指挥官",
                      suffixIcon: Icon(Icons.person_pin_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _addOrEditPreset(
                          scenario: scenarioController.text,
                          character: characterController.text,
                        ),
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text("存为预设"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("对话语言", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
                  const SizedBox(height: 8),
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
                            ],
                          ),
                        );
                      }).toList(),
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
                          _character = characterController.text;
                          _language = tempLanguage;
                          _selectedVoice = tempVoice;
                          _showDetails = tempShowDetails;
                          _isFormal = tempIsFormal;
                        });
                        _saveLanguage(tempLanguage);
                        Navigator.pop(context);
                        if (tempModelFile != null) _loadModel(tempModelFile!);
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
                              "${preset.scenario} | ${preset.character}",
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

  void _addOrEditPreset({ScenarioPreset? preset, int? index, String? scenario, String? character}) async {
    final nameController = TextEditingController(text: preset?.name ?? "");
    final scController = TextEditingController(text: preset?.scenario ?? scenario ?? "");
    final charController = TextEditingController(text: preset?.character ?? character ?? "");

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(preset == null ? "添加情境预设" : "编辑情境预设"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "预设名称", hintText: "例如：深夜食堂"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scController,
                decoration: const InputDecoration(labelText: "场景描述"),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: charController,
                decoration: const InputDecoration(labelText: "角色设定"),
                maxLines: 2,
              ),
            ],
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
          character: charController.text,
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

  Widget _buildWelcomeGuide(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.theater_comedy_rounded, size: 64, color: colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text("沉浸式场景对话", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text("点击右上角设置，开始您的角色扮演之旅", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    Widget list = ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
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
                enabled: !_isLoadingModel && !_isGenerating && _chatSession != null,
                decoration: InputDecoration(
                  hintText: _chatSession == null ? '会话已结束，请重新保存设定以开始' : '开始对话...',
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

class _GrammarAnalysisDialog extends StatefulWidget {
  final GemmaSkill gemmaSkill;
  final File modelFile;
  final String textContent;

  const _GrammarAnalysisDialog({
    required this.gemmaSkill,
    required this.modelFile,
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
    // 关键：当用户手动关闭、返回或弹窗消失时，强制停止 Gemma 的分析任务并关闭会话
    widget.gemmaSkill.close();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    try {
      await widget.gemmaSkill.initialize(modelFile: widget.modelFile);
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
