import 'package:Iris/perception/analyze_problem_page.dart';
import 'package:Iris/perception/full_duplex_chat_page.dart';
import 'package:Iris/perception/pronunciation_analysis_page.dart';
import 'package:Iris/perception/recognizeObject_page.dart';
import 'package:Iris/perception/scene_description_page.dart';
import 'package:Iris/perception/speech_translation_page.dart';
import 'package:Iris/perception/tone_analysis_page.dart';
import 'package:Iris/perception/translate_lines_page.dart';
import 'package:Iris/iris_assistant/browser_page.dart';
import 'package:flutter/material.dart';
import 'perception/text_extraction_page.dart';

class PerceptionPage extends StatefulWidget {
  const PerceptionPage({super.key});

  @override
  State<PerceptionPage> createState() => _PerceptionPageState();
}

class _PerceptionPageState extends State<PerceptionPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _selectedEngine = "百度";
  final Map<String, String> _engines = {
    "百度": "https://www.baidu.com/s?wd=",
    "搜狗": "https://www.sogou.com/web?query=",
    "必应": "https://cn.bing.com/search?q=",
    "Quark": "https://quark.sm.cn/s?q=",
    "头条": "https://so.toutiao.com/search?keyword=",
    "谷歌": "https://www.google.com/search?q=",
    "Yandex": "https://www.yandex.com/search/touch/?text=",
  };

  final Map<String, String> _directWeb = {
    "NHK NEWS": "https://news.web.nhk/newsweb",
    "JNTO": "https://www.japan-travel.cn",
    "UNIQLO": "https://www.uniqlo.com/jp",
    "NIKKEI": "https://www.nikkei.co.jp/nikkeiinfo/",
    "Jorudan": "https://www.jorudan.co.jp/norikae/",
    "Sony": "https://www.sony.co.jp/",
    "Nintendo": "https://www.nintendo.com/jp/index.html",
    "吉トカ": "https://www.ghibli.jp/"
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchFocusNode.addListener(() {
      setState(() {}); // 监听焦点变化以刷新 UI 显示直达链接
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      final url = "${_engines[_selectedEngine]}${Uri.encodeComponent(query)}";
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BrowserPage(url: url, title: "$_selectedEngine搜索: $query"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // 点击空白处收起键盘和直达链接
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('感知', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        body: Column(
          children: [
            _buildSearchSection(colorScheme),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '观世'),
                Tab(text: '闻讯'),
              ],
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSeeWorldGrid(colorScheme),
                  _buildListenNewsGrid(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection(ColorScheme colorScheme) {
    return Column(
      children: [
        _buildSearchBar(colorScheme),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _searchFocusNode.hasFocus 
            ? _buildDirectWebLinks(colorScheme)
            : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildDirectWebLinks(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.start,
        children: _directWeb.entries.map((entry) {
          final iconColor = _getIconColor(entry.key);
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BrowserPage(url: entry.value, title: entry.key),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: iconColor.withValues(alpha: 0.1)),
                    ),
                    child: Center(
                      child: Text(
                        entry.key[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.key,
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getIconColor(String name) {
    if (name.isEmpty) return Colors.grey;
    final List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.brown,
      Colors.deepOrange,
      Colors.blueGrey,
    ];
    // 根据首字母的 codeUnit 取模，确保相同首字母颜色一致，不同首字母尽量区分
    final int index = name.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            DropdownButton<String>(
              value: _selectedEngine,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, size: 20),
              menuMaxHeight: 300, // 限制高度
              alignment: AlignmentDirectional.bottomStart, // 向下对齐展开
              borderRadius: BorderRadius.circular(15),
              items: _engines.keys.map((String engine) {
                return DropdownMenuItem<String>(
                  value: engine,
                  child: Text(engine, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedEngine = value);
                }
              },
            ),
            const VerticalDivider(width: 1, indent: 10, endIndent: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode, // 绑定焦点
                decoration: const InputDecoration(
                  hintText: '搜索万物...',
                  hintStyle: TextStyle(fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                onSubmitted: (_) => _handleSearch(),
              ),
            ),
            IconButton(
              icon: Icon(Icons.search, color: colorScheme.primary),
              onPressed: _handleSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeeWorldGrid(ColorScheme colorScheme) {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _buildModuleCard(
          icon: Icons.text_snippet_rounded,
          title: '文字提取',
          subtitle: 'OCR 识别文本',
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TextExtractionPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.landscape_rounded,
          title: '场景描述',
          subtitle: 'AI 描述画面',
          color: Colors.green,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SceneDescriptionPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.image_search_rounded,
          title: '看图识物',
          subtitle: '识别物体品类',
          color: Colors.orange,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RecognizeObjectPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.translate_rounded,
          title: '台词翻译',
          subtitle: '精准译文分析',
          color: Colors.purple,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TranslateLinesPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.psychology_rounded,
          title: '题目分析',
          subtitle: '拍照解题思路',
          color: Colors.red,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AnalyzeProblemPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildListenNewsGrid(ColorScheme colorScheme) {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _buildModuleCard(
          icon: Icons.record_voice_over_rounded,
          title: '发音分析',
          subtitle: '纠正口语发音',
          color: Colors.teal,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PronunciationAnalysisPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.sentiment_satisfied_rounded,
          title: '语气分析',
          subtitle: '洞察情感波动',
          color: Colors.pink,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ToneAnalysisPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.g_translate_rounded,
          title: '语音翻译',
          subtitle: '实时同声传译',
          color: Colors.indigo,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SpeechTranslationPage()),
            );
          },
        ),
        _buildModuleCard(
          icon: Icons.forum_rounded,
          title: '全双工对话',
          subtitle: '实时语音交互',
          color: Colors.deepOrange,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const FullDuplexChatPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildModuleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.1)),
      ),
      color: color.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
