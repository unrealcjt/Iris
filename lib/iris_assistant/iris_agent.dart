
import 'package:Iris/iris_assistant/iris_tools.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'mascot_controller.dart';

class AgentTurn {
  final String userTask;
  String thinking;
  String answer;
  String? activeTool;
  bool isRunning;
  Map<String, dynamic>? webViewData;
  double webViewHeight = 300.0; // 记录高度
  String? lastSyncedJson; // 记录上次同步的 JSON，防止重复

  AgentTurn({
    required this.userTask,
    this.thinking = "",
    this.answer = "",
    this.activeTool,
    this.isRunning = true,
    this.webViewData,
  });
}

class IrisAgent extends ChangeNotifier {
  final List<AgentTurn> _history = [];
  List<AgentTurn> get history => _history;

  bool _isRoleplaying = false;
  bool get isRoleplaying => _isRoleplaying;

  set isRoleplaying(bool value) {
    _isRoleplaying = value;
    notifyListeners();
  }

  InferenceModel? get _currentModel => MascotController().model;
  InferenceChat? _currentChat;
  Future<void>? _initFuture;
  bool _isStopped = false;
  int _callTimes = 0;
  final _maxAllowedCallTimes = 12;

  bool get isAnyTaskRunning => _history.isNotEmpty && _history.last.isRunning;

  Future<void> closeChat() async {
    _currentChat?.close();
    _currentChat = null;
  }

  Future<void> initChat({bool isThinking = false}) async {
    if (_currentChat != null || _currentModel == null) return;
    
    // 如果已经在初始化中，则等待现有的 Future
    if (_initFuture != null) return _initFuture;

    _initFuture = _doInitChat(isThinking: isThinking);
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _doInitChat({bool isThinking = false}) async {
    // 提前加载 SKILL 提示词
    String SKILL = await IrisTools().generateSkillPrompt();

    _currentChat = await _currentModel!.openChat(
      isThinking: isThinking,
      modelType: ModelType.gemma4,
      supportsFunctionCalls: true,
      systemInstruction: """
You are an AI assistant that helps users by answering questions and completes tasks. If you are unable to solve the user's problem, please follow the steps below to use the skills.

CRITICAL RULE: You MUST execute all steps silently. Do NOT generate or output any internal thoughts, reasoning, explanations, or intermediate text at ANY step.

1. First, find the most relevant skill from the following list:

${SKILL}

After this step you MUST go to next step. You MUST NOT use `run_intent` under any circumstances at this step.

2. If a relevant skill exists, use the `load_skill` tool to read its instructions. You MUST NOT use `run_intent` under any circumstances at this step.

3. Follow the skill's instructions exactly to complete the task. You MUST NOT output any intermediate thoughts or status updates. No exceptions! Output ONLY the final result when successful. It should contain one-sentence summary of the action taken, and the final result of the skill.

4. If no relevant skill is found, Reply to the user in Chinese based on your knowledge and inform the user of the problem you have encountered.
""",
      tools: IrisTools.all
    );
  }

  Future<void> agentTask({required String task, bool isThinking = false}) async {
    if (_currentModel == null) return;

    _isStopped = false;
    _callTimes = 0;

    late AgentTurn activeTurn;

    if (_isRoleplaying && _history.isNotEmpty) {
      // 角色扮演模式：复用最后一轮（包含 WebView 的那一轮）
      activeTurn = _history.lastWhere((t) => t.webViewData != null);
      activeTurn.thinking = "";
      activeTurn.answer = "";
      activeTurn.lastSyncedJson = null; // 重置同步标记，允许新一轮同步
      // 关键修复：清除旧的同步数据，防止新任务开始时 WebView 频繁回跳到旧状态
      if (activeTurn.webViewData != null) {
        activeTurn.webViewData!['jsonData'] = null;
      }
      activeTurn.isRunning = true;
    } else {
      // 普通模式：新增一轮
      activeTurn = AgentTurn(userTask: task);
      _history.add(activeTurn);
    }
    
    notifyListeners();

    // 关键优化：显式让出控制权给 UI 线程，确保上一行添加的消息能立即被渲染，消除“卡顿感”
    // 使用 50ms 延迟确保 Flutter 引擎至少有 1-3 帧的时间来渲染用户刚刚发送的消息
    await Future.delayed(const Duration(milliseconds: 50));

    if (_currentChat == null) {
      await initChat(isThinking: isThinking);
    }
    
    if (_currentChat == null) return;

    final userMsg = Message.text(text: task, isUser: true);
    _currentChat!.addQueryChunk(userMsg);

    bool shouldContinue = true;
    while (shouldContinue && _callTimes <= _maxAllowedCallTimes && !_isStopped) {
      shouldContinue = await _runReActStep(activeTurn);
    }

    activeTurn.isRunning = false;
    activeTurn.activeTool = null;
    notifyListeners();
  }

  Future<bool> _runReActStep(AgentTurn turn) async {
    final stream = _currentChat!.generateChatResponseAsync();
    List<FunctionCallResponse> pendingCalls = [];

    await for (final response in stream) {
      if (_isStopped) break;
      
      if (response is ThinkingResponse) {
        turn.thinking += response.content;
        notifyListeners();
      } else if (response is TextResponse) {
        final token = response.token;
        if (token.contains('{"role":') || token.contains('"tool_calls":')) continue;
        turn.answer += token;
        notifyListeners();
      } else if (response is FunctionCallResponse) {
        print("函数调用\n${response.args.toString()}");
        pendingCalls.add(response);
      } else if (response is ParallelFunctionCallResponse) {
        pendingCalls.addAll(response.calls);
      }
    }

    if (pendingCalls.isNotEmpty) {
      for (final call in pendingCalls) {
        await _executeTool(call, turn);
        if (_callTimes > _maxAllowedCallTimes) break;
      }
      return true;
    }
    return false;
  }

  Future<void> _executeTool(FunctionCallResponse call, AgentTurn turn) async {
    if (_isStopped) return;
    _callTimes++;
    
    turn.activeTool = call.name;
    notifyListeners();

    Map<String, dynamic> toolResponse = await IrisTools().executeFunction(call.name, call.args);

    if (toolResponse['status'] == 'render_webview') {
      turn.webViewData = toolResponse;
      // 仅在工具执行成功时触发一次状态切换
      if (toolResponse['webName'] == 'galGame') {
        _isRoleplaying = true;
      }
      notifyListeners();
    }

    await _currentChat!.addQueryChunk(
      Message.toolResponse(toolName: call.name, response: toolResponse)
    );
  }

  Future<void> stopTask() async {
    _isStopped = true;
    if (_history.isNotEmpty) {
      _history.last.isRunning = false;
    }
    await _currentChat?.stopGeneration();
    notifyListeners();
  }

  Future<void> injectInfo(String msg) async {
    Message injMsg = Message.text(text: msg, isUser: true);
    _currentChat!.addQueryChunk(injMsg);
  }

  void clearHistory() {
    _history.clear();
    _currentChat = null;
    notifyListeners();
  }
}
