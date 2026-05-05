import 'package:flutter/material.dart';

class PerceptionPage extends StatefulWidget {
  const PerceptionPage({super.key});

  @override
  State<PerceptionPage> createState() => _PerceptionPageState();
}

class _PerceptionPageState extends State<PerceptionPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('感知', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '观世'),
            Tab(text: '闻讯'),
          ],
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSeeWorldGrid(colorScheme),
          _buildListenNewsGrid(colorScheme),
        ],
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
          onTap: () {},
        ),
        _buildModuleCard(
          icon: Icons.landscape_rounded,
          title: '场景描述',
          subtitle: 'AI 描述画面',
          color: Colors.green,
          onTap: () {},
        ),
        _buildModuleCard(
          icon: Icons.image_search_rounded,
          title: '看图识物',
          subtitle: '识别物体品类',
          color: Colors.orange,
          onTap: () {},
        ),
        _buildModuleCard(
          icon: Icons.translate_rounded,
          title: '台词翻译',
          subtitle: '精准译文分析',
          color: Colors.purple,
          onTap: () {},
        ),
        _buildModuleCard(
          icon: Icons.psychology_rounded,
          title: '题目分析',
          subtitle: '拍照解题思路',
          color: Colors.red,
          onTap: () {},
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
          onTap: () {},
        ),
        _buildModuleCard(
          icon: Icons.sentiment_satisfied_rounded,
          title: '语气分析',
          subtitle: '洞察情感波动',
          color: Colors.pink,
          onTap: () {},
        ),
        _buildModuleCard(
          icon: Icons.g_translate_rounded,
          title: '语音翻译',
          subtitle: '实时同声传译',
          color: Colors.indigo,
          onTap: () {},
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
        side: BorderSide(color: color.withOpacity(0.1)),
      ),
      color: color.withOpacity(0.05),
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
                  color: color.withOpacity(0.1),
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
