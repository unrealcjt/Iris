
import 'package:Iris/iris_assistant/iris_tools.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'mascot_controller.dart';

class IrisAgent extends ChangeNotifier {

  String? _thinkingContent;
  String? _currentTool;
  String? _answerContent;
  
  String? get thinkingContent => _thinkingContent;
  String? get currentTool => _currentTool;
  String? get answerContent => _answerContent;
  bool get isThinkingMode => _isThinkingMode;

  InferenceModel? get _currentModel => MascotController().model;
  InferenceChat? _currentChat;
  bool _isThinkingMode = false;
  bool _isStopped = false;
  int _callTimes = 0;
  final _maxAllowedCallTimes = 8;

  Future<void> agentTask({required String task, bool isThinking = false}) async {
    if (_currentModel == null) {
      return;
    }

    _isStopped = false;

    // 初始化状态
    _callTimes = 0;
    _thinkingContent = "";
    _answerContent = "";
    _currentTool = null;

    _currentChat = await _currentModel!.createChat(
      isThinking: isThinking,
      modelType: ModelType.gemma4,
      supportsFunctionCalls: true,
      systemInstruction: "You are an intelligence agent. Use tools to complete tasks. "
          "IMPORTANT: When using a tool, ONLY output the tool call in the standard format. "
          "Reply user in Chinese",
      tools: IrisTools.all
    );

    final userMsg = Message.text(text: task, isUser: true);
    _currentChat!.addQueryChunk(userMsg);

    // 使用迭代循环 (ReAct loop) 替代递归，提高安全性和可控性
    bool shouldContinue = true;
    while (shouldContinue && _callTimes <= _maxAllowedCallTimes && !_isStopped) {
      shouldContinue = await _runReActStep();
    }

    if (_callTimes > _maxAllowedCallTimes) {
      debugPrint("超过最大调用次数");
      _answerContent = (_answerContent ?? "") + "\n[System: Maximum tool call limit reached]";
      notifyListeners();
    }
  }

  /// 执行一轮推理和响应处理
  /// 返回 true 表示模型触发了工具调用，需要继续下一轮对话
  /// 返回 false 表示模型输出了最终结果或流程结束
  Future<bool> _runReActStep() async {
    final stream = _currentChat!.generateChatResponseAsync();

    _isThinkingMode = true;
    notifyListeners();

    List<FunctionCallResponse> pendingCalls = [];

    await for (final response in stream) {
      if (response is ThinkingResponse) {
        print("思考");
        _thinkingContent = (_thinkingContent ?? "") + response.content;
        notifyListeners();
      } else if (response is TextResponse) {
        final token = response.token;
        // 过滤掉包含工具调用 JSON 特征的文本 Token
        if (token.contains('{"role":') || 
            token.contains('"tool_calls":') || 
            token.contains('"arguments":') ||
            token.contains('"function":')) {
          continue;
        }
        
        print("文本");
        _isThinkingMode = false;
        _answerContent = (_answerContent ?? "") + token;
        notifyListeners();
      } else if (response is FunctionCallResponse) {
        print("函数调用");
        pendingCalls.add(response);
      } else if (response is ParallelFunctionCallResponse) {
        print("多个函数调用");
        pendingCalls.addAll(response.calls);
      }
    }

    // 流处理完毕
    _isThinkingMode = false;
    notifyListeners();

    // 处理工具调用逻辑
    if (pendingCalls.isNotEmpty) {
      for (final call in pendingCalls) {
        await _executeTool(call);
        if (_callTimes > _maxAllowedCallTimes) break;
      }
      return true; // 执行完工具后，需要将结果喂回模型进行下一轮推理
    }

    return false; // 没有工具调用，任务结束
  }

  /// 封装工具执行逻辑
  Future<void> _executeTool(FunctionCallResponse call) async {
    if (_isStopped) return;
    _callTimes++;
    if (_callTimes > _maxAllowedCallTimes) return;

    String funName = call.name;
    final args = call.args;

    debugPrint("执行工具逻辑: $funName, 参数: $args");
    
    _currentTool = funName;
    notifyListeners();

    Map<String, dynamic> toolResponse = await IrisTools().executeFunction(funName, args);

    _currentTool = null;
    notifyListeners();

    // 将工具返回结果存入对话上下文
    await _currentChat!.addQueryChunk(
        Message.toolResponse(
            toolName: funName,
            response: toolResponse
        )
    );
  }

  Future<void> stopTask() async {
    _isStopped = true;
    await _currentChat?.stopGeneration();
    _isThinkingMode = false;
    notifyListeners();
  }
}
