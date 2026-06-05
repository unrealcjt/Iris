import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 在文件顶部的 import 区域添加：
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class BrowserPage extends StatefulWidget {
  final String url;
  final String title;

  const BrowserPage({super.key, required this.url, this.title = "浏览器"});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with SingleTickerProviderStateMixin {
  InAppWebViewController? _webViewController;
  double _progress = 0;
  String _currentUrl = "";
  List<Map<String, String>> _favorites = [];
  bool _canGoBack = false; // 记录网页是否可以回退
  
  // 下载相关
  Map<String, double> _activeDownloads = {};
  List<Map<String, String>> _downloadHistory = [];
  Set<int> _selectedHistoryIndices = {};
  Set<String> _detectedVideos = {}; // 嗅探到的视频资源

  // 工具栏显示控制
  bool _showBars = true;
  double _lastScrollY = 0;
  bool _isTransitioning = false; // 用于屏蔽动画期间的滚动干扰

  // 翻译气泡相关
  final GemmaSkill _gemmaSkill = GemmaSkill();
  String _translationResult = "";
  Offset? _bubblePosition;
  bool _showTranslationBubble = false;
  bool _isTranslating = false;

  // 听视频/字幕相关
  String _liveSubtitleText = "";
  bool _isProcessingAudio = false;

  final String _videoEmbedScript = """
  (function() {
    if (window.__iris_buttons_injected__) return;
    window.__iris_buttons_injected__ = true;
  
    // 1. 深度穿透搜寻所有的 video 标签
    function findAllVideos(root = document) {
      let videos = Array.from(root.querySelectorAll('video'));
      const elements = root.querySelectorAll('*');
      for (let el of elements) {
        if (el.shadowRoot) {
          videos = videos.concat(findAllVideos(el.shadowRoot));
        }
      }
      return videos;
    }
  
    function injectButtons(video) {
      const targetParent = video.parentElement || video.parentNode;
      if (!targetParent || targetParent.querySelector('.iris-video-controls')) return;
  
      // 创建按钮容器，默认设置 opacity 为 0（隐藏），并加入 transition 过渡动画
      const container = document.createElement('div');
      container.className = 'iris-video-controls';
      container.style.cssText = 'position: absolute; top: 15px; left: 15px; z-index: 2147483647; display: flex; gap: 8px; background: rgba(0,0,0,0.7); padding: 8px; border-radius: 8px; pointer-events: auto; opacity: 0; transition: opacity 0.3s ease-in-out;';
  
      const btnDownload = document.createElement('button');
      btnDownload.innerText = '⬇️ 下载';
      btnDownload.style.cssText = 'background: #e91e63; color: white; border: none; padding: 6px 10px; border-radius: 4px; cursor: pointer; font-size: 12px; font-weight: bold;';
      btnDownload.onclick = function(e) {
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('irisVideoAction', { action: 'download', url: video.currentSrc || video.src });
      };
  
      container.appendChild(btnDownload);
  
      if (window.getComputedStyle(targetParent).position === 'static') {
        targetParent.style.position = 'relative';
      }
      targetParent.appendChild(container);
  
      // ================== 【核心控制逻辑：智能同步隐显】 ==================
      let fadeTimer = null;
  
      // 显示按钮的函数
      function showControls() {
        container.style.opacity = '1';
        container.style.pointerEvents = 'auto';
        
        // 重置定时器：如果视频在播放，手势静止 3 秒后自动淡出
        clearTimeout(fadeTimer);
        if (!video.paused) {
          fadeTimer = setTimeout(hideControls, 3000);
        }
      }
  
      // 隐藏按钮的函数
      function hideControls() {
        // 只有在视频正在播放时才允许自动隐藏（暂停时控制条常亮，按钮也应常亮）
        if (!video.paused) {
          container.style.opacity = '0';
          container.style.pointerEvents = 'none'; // 隐藏时禁用点击，防止误触
        }
      }
  
      // 监听各类交互事件，保持与原生/自定义控制条的唤醒逻辑同步
      // 兼容 PC(Hover) 和 移动端(Touch/Click)
      targetParent.addEventListener('mousemove', showControls);
      targetParent.addEventListener('touchstart', showControls, {passive: true});
      targetParent.addEventListener('click', showControls);
  
      // 监听视频状态变更
      video.addEventListener('play', showControls);
      video.addEventListener('pause', showControls); // 暂停时强制唤醒并保持可见
      video.addEventListener('seeking', showControls); // 进度条拖动时显示
  
      // 初始状态触发一次显示
      showControls();
      // ===================================================================
    }
  
    function scanAndInject() {
      findAllVideos().forEach(injectButtons);
    }
  
    scanAndInject();
    setInterval(scanAndInject, 2000);
  })();
  """;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _loadFavorites();
    _loadDownloadHistory();
  }

  // --- 辅助方法：安全切换工具栏 ---
  void _toggleBars(bool show) {
    if (_showBars == show || _isTransitioning) return;
    setState(() {
      _showBars = show;
      _isTransitioning = true;
    });
    // 延迟恢复，等待布局稳定
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _isTransitioning = false;
    });
  }

  // --- 持久化数据加载 ---
  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favList = prefs.getStringList('browser_favorites') ?? [];
    setState(() {
      _favorites = favList.map((item) {
        final parts = item.split('|');
        return {'title': parts[0], 'url': parts[1]};
      }).toList();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = _favorites.map((f) => "${f['title']}|${f['url']}").toList();
    await prefs.setStringList('browser_favorites', favList);
  }

  Future<void> _loadDownloadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyList = prefs.getStringList('browser_download_history') ?? [];
    setState(() {
      _downloadHistory = historyList.map((item) {
        final parts = item.split('|');
        return {'name': parts[0], 'url': parts[1], 'date': parts.length > 2 ? parts[2] : ''};
      }).toList();
    });
  }

  Future<void> _saveDownloadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyList = _downloadHistory.map((h) => "${h['name']}|${h['url']}|${h['date']}").toList();
    await prefs.setStringList('browser_download_history', historyList);
  }

  // --- 核心功能实现 ---
  void _toggleFavorite() {
    final index = _favorites.indexWhere((f) => f['url'] == _currentUrl);
    setState(() {
      if (index != -1) {
        _favorites.removeAt(index);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已取消收藏")));
      } else {
        _favorites.add({'title': widget.title, 'url': _currentUrl});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已添加收藏")));
      }
    });
    _saveFavorites();
  }

  Future<void> _handleDownload(DownloadStartRequest request) async {
    final url = request.url.toString();
    final isM3U8 = url.toLowerCase().contains('.m3u8');
    String fileName = p.basename(url.split('?').first);
    
    if (isM3U8) {
      fileName = fileName.replaceAll('.m3u8', '.mp4');
      if (!fileName.endsWith('.mp4')) fileName += '.mp4';
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认下载"),
        content: Text("文件名: $fileName\n\n是否下载该文件？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("下载")),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      final filePath = p.join(directory!.path, fileName);
      
      setState(() => _activeDownloads[fileName] = 0.0);

      if (isM3U8) {
        _startM3u8Download(url, filePath, fileName);
      } else {
        _startNormalDownload(url, filePath, fileName);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("下载失败: $e")));
    }
  }

  void _showToast(String message) {
    // 先清除之前还没消失的提示，避免提示堆积
    ScaffoldMessenger.of(context).clearSnackBars();

    // 弹出一个简短的提示条
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2), // 2秒后自动消失
        behavior: SnackBarBehavior.floating,  // 悬浮样式，看起来更像 Toast
      ),
    );
  }

  Future<void> _startM3u8Download(String url, String filePath, String fileName) async {
    setState(() {
      _activeDownloads[fileName] = 0.0;
    });

    try {
      String outputPath = filePath;
      if (outputPath.endsWith('.m3u8')) {
        outputPath = outputPath.replaceAll('.m3u8', '.mp4');
      } else if (!outputPath.endsWith('.mp4')) {
        outputPath = p.setExtension(outputPath, '.mp4');
      }

      final safeFileName = fileName.endsWith('.m3u8')
          ? fileName.replaceAll('.m3u8', '.mp4')
          : (fileName.contains('.') ? p.setExtension(fileName, '.mp4') : '$fileName.mp4');

      // =========== 【核心修复：提取浏览器身份凭证】 ===========
      // 1. 获取当前 WebView 的真实 User-Agent
      String userAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";
      if (_webViewController != null) {
        final customUa = await _webViewController!.getSettings().then((s) => s?.userAgent);
        if (customUa != null && customUa.isNotEmpty) userAgent = customUa;
      }

      // 2. 获取当前域名的 Cookie
      String cookieHeader = "";
      try {
        final cookies = await CookieManager.instance().getCookies(url: WebUri(_currentUrl));
        if (cookies.isNotEmpty) {
          cookieHeader = cookies.map((c) => "${c.name}=${c.value}").join("; ");
        }
      } catch (cookieErr) {
        print("Cookie 提取失败: \$cookieErr");
      }

      // 3. 构造传递给 FFmpeg 的安全头部字符串
      // 注意：多个 header 之间在 FFmpeg 中需要用 \r\n 换行符隔开
      StringBuffer headersBuffer = StringBuffer();
      headersBuffer.write("User-Agent: $userAgent\r\n");
      headersBuffer.write("Referer: $_currentUrl\r\n");
      if (cookieHeader.isNotEmpty) {
        headersBuffer.write("Cookie: $cookieHeader\r\n");
      }
      final String ffmpegHeaders = headersBuffer.toString();

      // 4. 构建带 Headers 伪装的 FFmpeg 命令
      // -headers 参数必须放在 -i 之前，才会对输入的网络流生效
      final ffmpegCommand = '-headers "$ffmpegHeaders" -i "$url" -c copy -y "$outputPath"';
      // =======================================================

      _showToast("开始安全拉取并转换 M3U8 视频...");

      await FFmpegKit.executeAsync(
          ffmpegCommand,
              (session) async {
            final returnCode = await session.getReturnCode();

            if (ReturnCode.isSuccess(returnCode)) {
              setState(() {
                _activeDownloads.remove(fileName);
                _downloadHistory.insert(0, {
                  'name': safeFileName,
                  'url': outputPath,
                  'date': DateTime.now().toString().split('.')[0],
                });
                _saveDownloadHistory();
              });
              _showToast("视频下载并封装成功：$safeFileName");
            } else {
              final failStackTrace = await session.getFailStackTrace();
              print("FFmpeg 失败日志: \$failStackTrace");
              setState(() {
                _activeDownloads.remove(fileName);
              });
              _showToast("下载失败，请检查网络防护或重试");
            }
          },
              (log) {
            print("FFmpeg Log: \${log.getMessage()}");
          },
              (statistics) {
            setState(() {
              _activeDownloads[fileName] = 0.5;
            });
          }
      );

    } catch (e) {
      print("M3U8下载发生错误: \$e");
      setState(() {
        _activeDownloads.remove(fileName);
      });
      _showToast("下载初始化失败: \$e");
    }
  }

  Future<void> _startNormalDownload(String url, String filePath, String fileName) async {
    final response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    final total = response.contentLength ?? 0;
    int received = 0;
    final file = File(filePath);
    final sink = file.openWrite();

    await response.stream.map((chunk) {
      received += chunk.length;
      if (total > 0) setState(() => _activeDownloads[fileName] = received / total);
      return chunk;
    }).pipe(sink);

    await sink.close();
    _finishDownload(fileName, url);
  }

  void _finishDownload(String fileName, String url) {
    setState(() {
      _activeDownloads.remove(fileName);
      _downloadHistory.insert(0, {'name': fileName, 'url': url, 'date': DateTime.now().toString().split('.').first});
    });
    _saveDownloadHistory();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("下载完成: $fileName")));
  }

  Future<void> _handleBack() async {
    if (_showTranslationBubble) {
      setState(() => _showTranslationBubble = false);
      return;
    }
    if (_canGoBack) {
      await _webViewController?.goBack();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _startTranslation(String text, Offset position) async {
    setState(() {
      _translationResult = "正在翻译...";
      _bubblePosition = position;
      _showTranslationBubble = true;
      _isTranslating = true;
    });

    try {
      await _gemmaSkill.initialize();
      final stream = _gemmaSkill.japaneseTranslate(content: text, enableThinking: false);
      _translationResult = "";
      await for (final chunk in stream) {
        if (!mounted || !_showTranslationBubble) break;
        setState(() => _translationResult += chunk);
      }
    } catch (e) {
      setState(() => _translationResult = "翻译出错: $e");
    } finally {
      setState(() => _isTranslating = false);
    }
  }

  void _showFullDrawer(String title, Widget content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Future<void> _clearBrowserData() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("清除浏览数据"),
        content: const Text("这将清除所有缓存、Cookie 和本地存储的数据。确定要继续吗？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("清除", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await CookieManager.instance().deleteAllCookies();
        await InAppWebViewController.clearAllCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已清除浏览数据")));
          _webViewController?.reload();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("清除失败: $e")));
      }
    }
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMenuAction(Icons.star_border, "添加收藏", () { Navigator.pop(context); _toggleFavorite(); }),
            _buildMenuAction(Icons.bookmarks_outlined, "收藏夹", () { Navigator.pop(context); _showFavoritesDrawer(); }),
            _buildMenuAction(Icons.download_for_offline_outlined, "下载管理", () { Navigator.pop(context); _showDownloadsDrawer(); }),
            _buildMenuAction(Icons.video_library_outlined, "视频嗅探", () { Navigator.pop(context); _showVideoSnifferDrawer(); }),
            _buildMenuAction(Icons.delete_sweep_outlined, "清除数据", () { Navigator.pop(context); _clearBrowserData(); }),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 28), const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 12))]),
    );
  }

  void _showFavoritesDrawer() {
    _showFullDrawer("我的收藏", StatefulBuilder(
      builder: (context, setModalState) {
        return _favorites.isEmpty 
          ? const Center(child: Text("暂无收藏记录"))
          : ListView.separated(
              itemCount: _favorites.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final fav = _favorites[index];
                return ListTile(
                  title: Text(fav['title']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(fav['url']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(fav['url']!)));
                    Navigator.pop(context);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () { Clipboard.setData(ClipboardData(text: fav['url']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("链接已复制"))); }),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () { setState(() => _favorites.removeAt(index)); _saveFavorites(); setModalState(() {}); }),
                    ],
                  ),
                );
              },
            );
      }
    ));
  }

  void _showDownloadsDrawer() {
    _showFullDrawer("下载管理", DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: "当前下载"), Tab(text: "历史记录")], labelColor: Colors.pinkAccent, unselectedLabelColor: Colors.grey, indicatorColor: Colors.pinkAccent),
          Expanded(child: TabBarView(children: [_buildActiveDownloadsTab(), _buildDownloadHistoryTab()])),
        ],
      ),
    ));
  }

  Widget _buildActiveDownloadsTab() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return _activeDownloads.isEmpty 
          ? const Center(child: Text("暂无正在下载的任务"))
          : ListView.builder(
              itemCount: _activeDownloads.length,
              itemBuilder: (context, index) {
                String name = _activeDownloads.keys.elementAt(index);
                double prog = _activeDownloads[name]!;
                return ListTile(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: LinearProgressIndicator(value: prog, minHeight: 4), trailing: Text("${(prog * 100).toInt()}%"));
              },
            );
      }
    );
  }

  Widget _buildDownloadHistoryTab() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        if (_downloadHistory.isEmpty) return const Center(child: Text("暂无历史记录"));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Checkbox(value: _selectedHistoryIndices.length == _downloadHistory.length && _downloadHistory.isNotEmpty, onChanged: (val) { setModalState(() { if (val == true) { _selectedHistoryIndices = Set.from(Iterable.generate(_downloadHistory.length)); } else { _selectedHistoryIndices.clear(); } }); }),
                  const Text("全选"),
                  const Spacer(),
                  if (_selectedHistoryIndices.isNotEmpty)
                    TextButton.icon(icon: const Icon(Icons.delete_sweep, color: Colors.red), label: const Text("删除选中", style: TextStyle(color: Colors.red)), onPressed: () { setState(() { List<int> sortedIndices = _selectedHistoryIndices.toList()..sort((a, b) => b.compareTo(a)); for (var i in sortedIndices) { _downloadHistory.removeAt(i); } _selectedHistoryIndices.clear(); }); _saveDownloadHistory(); setModalState(() {}); }),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _downloadHistory.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _downloadHistory[index];
                  final isSelected = _selectedHistoryIndices.contains(index);
                  return ListTile(
                    leading: Checkbox(value: isSelected, onChanged: (val) { setModalState(() { if (val == true) { _selectedHistoryIndices.add(index); } else { _selectedHistoryIndices.remove(index); } }); }),
                    title: Text(item['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['url']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(item['date']!, style: const TextStyle(fontSize: 10, color: Colors.grey))]),
                    trailing: PopupMenuButton<String>(onSelected: (val) { if (val == 'copy') { Clipboard.setData(ClipboardData(text: item['url']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("链接已复制"))); } else if (val == 'delete') { setState(() => _downloadHistory.removeAt(index)); _saveDownloadHistory(); setModalState(() {}); } }, itemBuilder: (context) => [const PopupMenuItem(value: 'copy', child: Text("复制下载链接")), const PopupMenuItem(value: 'delete', child: Text("删除记录"))]),
                  );
                },
              ),
            ),
          ],
        );
      }
    );
  }

  void _showVideoSnifferDrawer() {
    _showFullDrawer("视频嗅探 (检测到 ${_detectedVideos.length} 个资源)", StatefulBuilder(
      builder: (context, setModalState) {
        if (_detectedVideos.isEmpty) return const Center(child: Text("未检测到可下载的视频资源"));
        final videoList = _detectedVideos.toList();
        return ListView.separated(
          itemCount: videoList.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final url = videoList[index];
            final isM3U8 = url.toLowerCase().contains(".m3u8");
            final fileName = p.basename(url.split('?').first);
            return ListTile(
              leading: Icon(isM3U8 ? Icons.featured_play_list : Icons.video_file, color: isM3U8 ? Colors.orange : Colors.blue),
              title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(isM3U8 ? "HLS流媒体(可能下载失败)" : "普通视频文件", style: TextStyle(color: isM3U8 ? Colors.orange : Colors.grey, fontSize: 10)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.download), onPressed: () => _handleDownload(DownloadStartRequest(url: WebUri(url), userAgent: "", contentLength: -1))),
                  IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () { Clipboard.setData(ClipboardData(text: url)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("链接已复制"))); }),
                ],
              ),
            );
          },
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _webViewController?.goBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: _showBars 
          ? AppBar(
              toolbarHeight: 56,
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _handleBack),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(_currentUrl, style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)), overflow: TextOverflow.ellipsis),
                ],
              ),
              actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => _webViewController?.reload())],
              bottom: _progress < 1.0 ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary))) : null,
            )
          : null,
        body: SafeArea(
          top: !_showBars,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useOnDownloadStart: true,
                  useOnLoadResource: true,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  verticalScrollBarEnabled: false,
                  cacheEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  safeBrowsingEnabled: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW, // 允许 HTTPS 页面加载 HTTP 音视频资源
                  hardwareAcceleration: true,
                ),
                contextMenu: ContextMenu(
                  settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true),
                  menuItems: [
                    ContextMenuItem(id: 0, title: "复制", action: () async { final selectedText = await _webViewController?.getSelectedText(); if (selectedText != null) { await Clipboard.setData(ClipboardData(text: selectedText)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已复制"))); } }),
                    ContextMenuItem(id: 1, title: "全选", action: () async { await _webViewController?.evaluateJavascript(source: "document.execCommand('selectAll', false, null);"); }),
                    ContextMenuItem(id: 2, title: "询问 Iris", action: () async { final selectedText = await _webViewController?.getSelectedText(); if (selectedText != null && selectedText.isNotEmpty) MascotController().activeMascot(selectedText); }),
                    ContextMenuItem(id: 3, title: "Iris朗读", action: () async { final selectedText = await _webViewController?.getSelectedText(); if (selectedText != null && selectedText.isNotEmpty) MascotController().speak(selectedText); }),
                    ContextMenuItem(id: 4, title: "Iris翻译", action: () async {
                      final selectedText = await _webViewController?.getSelectedText();
                      if (selectedText != null && selectedText.isNotEmpty) {
                        final rect = await _webViewController?.evaluateJavascript(source: "(function(){var s=window.getSelection();if(s.rangeCount>0){var r=s.getRangeAt(0).getBoundingClientRect();return {x:r.left,y:r.top,w:r.width,h:r.height};}return null;})()");
                        Offset pos = const Offset(50, 150);
                        if (rect != null) pos = Offset(rect['x'].toDouble(), rect['y'].toDouble() + rect['h'].toDouble());
                        _startTranslation(selectedText, pos);
                      }
                    }),
                  ],
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;

                  controller.addJavaScriptHandler(
                      handlerName: 'irisVideoAction',
                      callback: (args) {
                        final data = args[0] as Map;
                        final String action = data['action'];
                        final String videoUrl = data['url'];

                        if (videoUrl.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("未能成功获取该视频的有效链接")));
                          return;
                        }

                        if (action == 'download') {
                          // 触发你原有的下载确认和 FFmpeg 下载逻辑
                          _handleDownload(DownloadStartRequest(url: WebUri(videoUrl), userAgent: "", contentLength: -1));
                        }
                      }
                  );
                },
                onLoadResource: (controller, resource) {
                  final url = resource.url.toString();
                  // 1. 更严格的后缀匹配
                  final isVideo = RegExp(r'\.(mp4|m3u8|webm|avi|flv)(\?|$)').hasMatch(url.toLowerCase());
                  // 2. 排除常见的干扰项
                  final isNoise = url.contains(".html") || url.contains(".js") || url.contains(".css");

                  if (isVideo && !isNoise) {
                    if (!_detectedVideos.contains(url)) {
                      setState(() => _detectedVideos.add(url));
                    }
                    // 资源变化时（例如用户切换了集数），重新运行一次脚本确保新视频被挂载按钮
                    controller.evaluateJavascript(source: _videoEmbedScript);
                  }
                },
                onScrollChanged: (controller, x, y) {
                  if (_showTranslationBubble) setState(() => _showTranslationBubble = false);
                  if (_isTransitioning) return;
                  double dy = y.toDouble() - _lastScrollY;
                  if (dy.abs() > 64) { if (dy > 0 && _showBars && y > 150) _toggleBars(false); else if (dy < 0 && !_showBars) _toggleBars(true); _lastScrollY = y.toDouble(); }
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _currentUrl = url.toString();
                    _detectedVideos.clear(); // 页面开始加载时清空之前的嗅探结果
                  });
                },
                onLoadStop: (controller, url) async {
                  setState(() => _currentUrl = url.toString());
                  _canGoBack = await controller.canGoBack();

                  // 注入视频嵌入按钮代码
                  await controller.evaluateJavascript(source: _videoEmbedScript);
                },
                onProgressChanged: (controller, progress) async { setState(() => _progress = progress / 100); if (progress > 80) { _canGoBack = await controller.canGoBack(); if (mounted) setState(() {}); } },
                onDownloadStartRequest: (controller, request) => _handleDownload(request),
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  var uri = navigationAction.request.url;
                  if (uri != null && uri.scheme != "http" && uri.scheme != "https") return NavigationActionPolicy.CANCEL;
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              if (_showTranslationBubble && _bubblePosition != null)
                Positioned(
                  left: (_bubblePosition!.dx - 10).clamp(10, MediaQuery.of(context).size.width - 250),
                  top: (_bubblePosition!.dy + 10).clamp(10, MediaQuery.of(context).size.height - 300),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.pink[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3), width: 2)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [const Icon(Icons.translate, size: 14, color: Colors.pinkAccent), const SizedBox(width: 6), Text("Iris 翻译", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.pink[700]))]), IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.pinkAccent), onPressed: () => setState(() => _showTranslationBubble = false), constraints: const BoxConstraints(), padding: EdgeInsets.zero)]),
                          const Divider(height: 12),
                          Flexible(child: SingleChildScrollView(child: MarkdownBody(data: _translationResult, styleSheet: MarkdownStyleSheet(p: TextStyle(fontSize: 14, color: Colors.brown[900], height: 1.4))))),
                          if (_isTranslating) const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator(minHeight: 1, backgroundColor: Colors.transparent)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _showBars 
          ? BottomAppBar(height: 60, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => Navigator.pop(context)), IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () async { if (await _webViewController?.canGoBack() ?? false) _webViewController?.goBack(); }), IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 20), onPressed: () async { if (await _webViewController?.canGoForward() ?? false) _webViewController?.goForward(); }), IconButton(icon: const Icon(Icons.menu), onPressed: _showMenu)]))
          : null,
      ),
    );
  }
}
