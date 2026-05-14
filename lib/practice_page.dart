import 'package:Iris/practice/search_result_screen.dart';
import 'package:Iris/practice/trial_page.dart';
import 'package:Iris/practice/vocabulary_list_page.dart';
import 'package:Iris/utils/wa_colors.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jm/dictionary_service.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final TextEditingController _searchController = TextEditingController();
  final DictionaryService _dictService = DictionaryService();
  bool _isBookCreated = false;

  @override
  void initState() {
    super.initState();
    _checkBookStatus();
  }

  Future<void> _checkBookStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBookCreated = prefs.getBool('isVocabularyBookCreated') ?? false;
    });
  }

  Future<void> _createBook() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isVocabularyBookCreated', true);
    setState(() {
      _isBookCreated = true;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '修行',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(start: 24, bottom: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 搜索栏
                  _buildSearchBar(colorScheme, context),
                  const SizedBox(height: 32),
                  
                  _buildSectionTitle(context, '每日修习', Icons.auto_stories),
                  const SizedBox(height: 16),
                  
                  // 生词修习
                  if (!_isBookCreated)
                    _buildCreateBookCard(context)
                  else
                    _buildModuleCard(
                      context: context,
                      title: '生词修习',
                      subtitle: '温故而知新，夯实词汇基础',
                      icon: Icons.menu_book_rounded,
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const VocabularyListPage()),
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                  
                  // 试炼
                  _buildModuleCard(
                    context: context,
                    title: '试炼',
                    subtitle: '实战检验，提升语言运用能力',
                    icon: Icons.quiz_rounded,
                    color: Colors.orangeAccent,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TrialPage())
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme, BuildContext context) {
    return SearchAnchor(
      // 控制器可以帮你获取当前输入的内容
      searchController: SearchController(),
      builder: (BuildContext context, SearchController controller) {
        return SearchBar(
          controller: controller,
          padding: const WidgetStatePropertyAll<EdgeInsets>(
              EdgeInsets.symmetric(horizontal: 16.0)),
          onTap: () => controller.openView(), // 点击打开联想列表
          onChanged: (_) => controller.openView(),
          leading: const Icon(Icons.search),
          hintText: '搜索生词...',
          elevation: WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
          trailing: [
            IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _handleSearch(context, controller.text);
                }
              },
            )
          ],
        );
      },
      // 这里是关键：联想列表的构建逻辑
      suggestionsBuilder: (BuildContext context, SearchController controller) async {
        final String input = controller.value.text.trim();
        if (input.isEmpty) return [];

        final List<String> suggestions = await _dictService.getSuggestions(input);

        // 1. 构造一个固定的“搜索当前”组件
        final List<Widget> listItems = [
          ListTile(
            leading: const Icon(Icons.search, color: WaColors.akaRed),
            title: Text('搜索 "$input"',
                style: const TextStyle(fontWeight: FontWeight.bold, color: WaColors.akaRed)),
            onTap: () {
              controller.closeView(input);
              _handleSearch(context, input);
            },
          ),
          const Divider(height: 1), // 分割线
        ];

        // 2. 添加联想出的具体词条
        if (suggestions.isNotEmpty) {
          listItems.addAll(suggestions.map((suggestion) => ListTile(
            leading: const Icon(Icons.history_edu_rounded, size: 18),
            title: Text(suggestion),
            onTap: () {
              controller.text = suggestion;
              controller.closeView(suggestion);
              _handleSearch(context, suggestion);
            },
          )));
        } else {
          listItems.add(
              const ListTile(title: Text("查无此词，点击强制搜索", style: TextStyle(color: Colors.grey, fontSize: 13)))
          );
        }

        return listItems;
      }
    );
  }

  // 跳转逻辑
  void _handleSearch(BuildContext context, String query) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchResultScreen(query: query),
      ),
    );
  }

  Widget _buildCreateBookCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.library_add_rounded, size: 48, color: Colors.blueAccent),
          const SizedBox(height: 16),
          const Text(
            '尚未创建生词本',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '创建一个日语生词本，开始你的语言修行之旅',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _createBook,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('立即创建'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
