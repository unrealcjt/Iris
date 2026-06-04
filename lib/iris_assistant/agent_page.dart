
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'iris_agent.dart';
import 'mascot_controller.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final TextEditingController _taskController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final IrisAgent _agent = IrisAgent();

  @override
  void initState() {
    super.initState();
    _agent.addListener(_scrollToBottom);
    // 页面进入时即开始初始化会话，避免发送第一条消息时因创建会话导致的卡顿
    _agent.initChat(isThinking: MascotController().isThinkingMode);
  }

  @override
  void dispose() {
    _agent.removeListener(_scrollToBottom);
    _agent.closeChat();
    _taskController.dispose();
    _scrollController.dispose();
    _agent.stopTask();

    super.dispose();
  }

  void _runTask() {
    final task = _taskController.text.trim();
    if (task.isNotEmpty && !_agent.isAnyTaskRunning) {
      _taskController.clear();
      _agent.agentTask(task: task, isThinking: MascotController().isThinkingMode);
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Iris Agent", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            onPressed: () => setState(() => _agent.clearHistory()),
          )
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 背景图
          Positioned.fill(
            child: Image.asset(
              "assets/img/Iris_Scarlet.png",
              fit: BoxFit.cover,
            ),
          ),
          // 渐变遮罩层，提升文字可读性
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.6),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _agent,
                  builder: (context, _) {
                    if (_agent.history.isEmpty) {
                      return _buildEmptyState();
                    }
                    
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 108, 16, 16),
                  itemCount: _agent.history.length,
                  itemBuilder: (context, index) {
                    final turn = _agent.history[index];
                    return _buildTurnItem(turn);
                  },
                );
                  },
                ),
              ),
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: Colors.pinkAccent.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text("我是 Iris Agent", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 18)),
          const SizedBox(height: 8),
          Text("你可以让我帮你处理复杂的工具调用任务", style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildTurnItem(AgentTurn turn) {
    return Column(
      children: [
        // 用户消息气泡
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 40, bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.pinkAccent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Text(turn.userTask, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ),
        // Iris 回复区域
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(right: 20, bottom: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.pinkAccent,
                      child: ClipOval(
                        child: Image.asset(
                          "assets/img/icon_desk_v2.png",
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("Iris", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                if (turn.thinking.isNotEmpty && (!_agent.isRoleplaying || turn.webViewData == null)) 
                  _ThinkingBlock(thinking: turn.thinking),
                if (turn.activeTool != null && (!_agent.isRoleplaying || turn.webViewData == null)) 
                  _buildToolIndicator(turn.activeTool!),
                if (turn.webViewData != null) 
                  _WebViewMessage(data: turn.webViewData!, agent: _agent),
                if (turn.answer.isNotEmpty && (!_agent.isRoleplaying || turn.webViewData == null)) 
                  _buildAnswerBox(turn.answer),
                if (turn.isRunning && turn.answer.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolIndicator(String tool) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.build_circle_outlined, color: Colors.blueAccent, size: 14),
          const SizedBox(width: 6),
          Text("正在执行: $tool", style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAnswerBox(String answer) {
    return MarkdownBody(
      data: answer,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
        code: const TextStyle(backgroundColor: Colors.white10, color: Colors.amberAccent, fontSize: 14),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _taskController,
              onSubmitted: (_) => _runTask(),
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: "それでは始めましょう",
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: _agent,
            builder: (context, _) {
              final isRunning = _agent.isAnyTaskRunning;
              return GestureDetector(
                onTap: isRunning ? () => _agent.stopTask() : _runTask,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isRunning ? Colors.redAccent : Colors.pinkAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRunning ? Icons.stop_rounded : Icons.send_rounded,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WebViewMessage extends StatefulWidget {
  final Map<String, dynamic> data;
  final IrisAgent agent;
  const _WebViewMessage({
    required this.data, 
    required this.agent, 
  });

  @override
  State<_WebViewMessage> createState() => _WebViewMessageState();
}

class _WebViewMessageState extends State<_WebViewMessage> with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _webViewController;
  late final VoidCallback _agentListener;
  bool _isPageFinished = false;

  @override
  bool get wantKeepAlive => true; 

  // 获取该消息对应的原始数据模型
  AgentTurn get _turn => widget.agent.history.lastWhere((t) => t.webViewData == widget.data);

  @override
  void initState() {
    super.initState();

    // 监听后续模型回复
    _agentListener = () {
      if (widget.agent.isRoleplaying && _isPageFinished && widget.agent.history.isNotEmpty && _webViewController != null) {
        final lastTurn = widget.agent.history.last;
        
        // 我们只同步“属于本 WebView 所在轮次”的数据
        if (lastTurn != _turn) return;

        String? dataToSync;
        // 优先从最新的 answer 中提取 JSON
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(lastTurn.answer);
        
        if (jsonMatch != null) {
          dataToSync = jsonMatch.group(0);
        } else if (lastTurn.webViewData != null && lastTurn.webViewData!['jsonData'] != null) {
          dataToSync = lastTurn.webViewData!['jsonData'];
        }

        // 仅在数据完整且发生变化时同步
        if (dataToSync != null && _isValidJson(dataToSync) && dataToSync != _turn.lastSyncedJson) {
          _turn.lastSyncedJson = dataToSync;
          final escapedJson = jsonEncode(dataToSync);
          _webViewController?.evaluateJavascript(source: "if(window.onReceiveModelAction) window.onReceiveModelAction($escapedJson);");
          
          final webName = widget.data['webName'] ?? "";
          if (webName != 'galGame' && webName != 'dialogueAdventure') {
            Future.delayed(const Duration(milliseconds: 200), _updateHeight);
          }
        }
      }
    };
    widget.agent.addListener(_agentListener);
  }

  bool _isValidJson(String str) {
    try {
      jsonDecode(str);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _updateHeight() async {
    if (_webViewController == null) return;
    try {
      final result = await _webViewController!.evaluateJavascript(
        source: "document.documentElement.scrollHeight.toString()"
      );
      if (result == null) return;
      final String heightStr = result.toString();
      final double? height = double.tryParse(heightStr.replaceAll('"', ''));
      if (height != null && height > 0 && mounted) {
        setState(() {
          _turn.webViewHeight = height.clamp(100.0, 800.0);
        });
      }
    } catch (e) {
      debugPrint("获取 WebView 高度失败: $e");
    }
  }

  @override
  void dispose() {
    widget.agent.removeListener(_agentListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _turn.webViewHeight,
      margin: const EdgeInsets.only(bottom: 12),
      key: ObjectKey(widget.data), // 关键：使用 ObjectKey 锁定 WebView 实体
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: InAppWebView(
        initialFile: widget.data['htmlPath'],
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          controller.addJavaScriptHandler(
            handlerName: 'FlutterAgentBridge',
            callback: (args) {
              try {
                final String message = args[0];
                final data = jsonDecode(message);
                if (data['action'] == 'exit_roleplay') {
                  widget.agent.injectInfo("Role play has ended, Now recover the identity of AI assistant.");
                  widget.agent.isRoleplaying = false;
                } else if (data['action'] == 'update_height') {
                  if (data['height'] != null) {
                    setState(() => _turn.webViewHeight = (data['height'] as num).toDouble());
                  }
                }
              } catch (e) {
                debugPrint("解析 WebView 显示失败: $e");
              }
            },
          );
        },
        onLoadStop: (controller, url) async {
          setState(() => _isPageFinished = true);
          
          await controller.evaluateJavascript(source: """
            window.FlutterAgentBridge = {
              postMessage: function(message) {
                window.flutter_inappwebview.callHandler('FlutterAgentBridge', message);
              }
            };
          """);

          // 如果已有同步过的 JSON，优先同步最新的，否则同步初始数据
          final jsonData = _turn.lastSyncedJson ?? widget.data['jsonData'] ?? "{}";
          final escapedJson = jsonEncode(jsonData);
          controller.evaluateJavascript(source: "if(window.onReceiveModelAction) window.onReceiveModelAction($escapedJson);");
          
          _updateHeight();
        },
      ),
    );
  }
}

class _ThinkingBlock extends StatefulWidget {
  final String thinking;
  const _ThinkingBlock({required this.thinking});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Row(
              children: [
                const Icon(Icons.psychology_outlined, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Text("Iris 正在思考...", 
                  style: TextStyle(color: Colors.amber.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            Text(
              widget.thinking,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
