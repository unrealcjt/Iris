import 'package:Iris/custom_component/iris_selection_area.dart';
import 'package:Iris/utils/edge_tts_service.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'package:flutter/material.dart';
import 'package:Iris/jm/dictionary_service.dart';
import 'package:Iris/jm/models.dart';

import 'package:Iris/utils/wa_colors.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Iris/jm/jm_parser.dart';
import 'vocabulary_service.dart';
import 'vocabulary_model.dart';

class SearchResultScreen extends StatefulWidget {
  final String query;
  const SearchResultScreen({super.key, required this.query});

  @override
  State<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends State<SearchResultScreen> {
  final DictionaryService _dictService = DictionaryService();
  final VocabularyService _vocabService = VocabularyService();
  JmEntry? _selectedEntry; // 记录当前点击的单词
  bool _isCollected = false;
  String query = "";
  
  final _ttsService = EdgeTtsService();
  final _gemmaSkill = GemmaSkill();
  String _exampleSentence = "";
  bool _isGeneratingExample = false;

  Future<void> _generateExample(String word) async {
    if (_isGeneratingExample) return;

    setState(() {
      _isGeneratingExample = true;
      _exampleSentence = "";
    });

    try {
      await _gemmaSkill.initialize();
      final stream = _gemmaSkill.exampleSentenceByWord(word: word);
      
      await for (final chunk in stream) {
        setState(() {
          _exampleSentence += chunk;
        });
      }
    } catch (e) {
      setState(() => _exampleSentence = "例句生成失败: $e");
    } finally {
      setState(() => _isGeneratingExample = false);
    }
  }

  void _showKanjiDetail(String char) async {
    final kanji = await _dictService.getKanjiInfo(char);
    if (kanji == null) return;
    if (!mounted) return;

    final filteredMeanings = kanji.readingMeaning?.meanings
        .where((m) =>
    m.lang == null || m.lang == '' || m.lang == 'en' || m.lang == "zh")
        .map((m) =>
    m.lang == null ? m.value : (m.lang == "en" ? "英" : (m.lang == "zh"
        ? "中"
        : "")) + ". " + m.value)
        .toList() ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许弹窗高度超过半屏
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // 使用 DraggableScrollableSheet 可以让用户向上拉大弹窗
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          // 初始高度 60%
          minChildSize: 0.4,
          // 最小高度 40%
          maxChildSize: 0.9,
          // 最大高度 90%
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController, // 绑定滚动控制器
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部：汉字大字和基础信息
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(kanji.literal, style: const TextStyle(
                          fontSize: 60, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('笔画: ${kanji.misc?['stroke_count'] ??
                              '未知'}'),
                          Text('JLPT: N${kanji.misc?['jlpt'] ?? '未知'}'),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // 读音部分
                  const Text('读音', style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  // 使用 Wrap 替代 Column 渲染读音，可以更有效地利用横向空间
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: kanji.readingMeaning?.readings.map((r) =>
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: r.type == 'ja_on' ? Colors.red.withOpacity(
                                0.1) : Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.type == 'ja_on' ? '音' : '训',
                                  style: TextStyle(fontSize: 10,
                                      color: r.type == 'ja_on'
                                          ? Colors.red
                                          : Colors.blue)),
                              const SizedBox(width: 6),
                              Text(r.value,
                                  style: const TextStyle(fontSize: 16)),
                            ],
                          ),
                        )).toList() ?? [],
                  ),

                  const SizedBox(height: 24),

                  // 含义部分
                  const Text('含义', style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: filteredMeanings
                        .asMap()
                        .entries
                        .map((entry) {
                      int index = entry.key + 1; // 序号从 1 开始
                      String value = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 序号部分
                            Text(
                              '$index. ',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            // 文本内容部分
                            Expanded(
                              child: Text(
                                value,
                                style: const TextStyle(
                                    fontSize: 15, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                  // 留白，防止内容贴底
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    query = widget.query;
    return Scaffold(
      appBar: AppBar(title: Text('搜索结果: ${widget.query}')),
      body: Column(
        children: [
          // 上半部分：搜索到的列表
          Expanded(
              flex: 2, // 列表占 2 份空间
              child: Material(
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<List<JmEntry>>(
                  future: _dictService.searchEntries(widget.query),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final results = snapshot.data ?? [];
                    if (results.isEmpty)
                      return IrisSelectionArea(
                        child: Container(
                          width: double.infinity,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24.0),
                          child: MarkdownBody(
                            data: "😅(￣﹃￣) !!!\n\n没有找到 `${query}` 相关词条捏。\n\n该功能用于搜索日语，词典中收录假名和汉字，但注意不包含纯汉语词汇。\n\n如果需要其他功能，你可以长按选择该词条让Iris帮你解析。",
                            styleSheet: MarkdownStyleSheet(
                              blockquoteAlign: WrapAlignment.center,
                              p: const TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                height: 1.6,
                                shadows: [Shadow(color: Colors.black12, blurRadius: 2)],
                              ),
                              code: const TextStyle(
                                  color: Colors.redAccent,
                                  fontFamily: 'monospace',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        )
                      );

                    return ListView
                        .builder( // 这里改为 builder，因为我们要在 itemBuilder 里自定义间距
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      // 给列表上下加点留白
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final entry = results[index];
                        final isSelected = _selectedEntry?.entSeq ==
                            entry.entSeq;

                        final allKanjiText = entry.kanji.map((k) => k.written).join('、');

                        // --- 这里就是那段“现代感处理”的代码 ---
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 16,
                              vertical: 4), // 外边距，产生“卡片悬浮”感
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors
                                .transparent,
                            borderRadius: BorderRadius.circular(12),
                            // 选中时显示绯红色边框，不选中时没有边框
                            border: Border.all(
                              color: isSelected ? WaColors.akaRed.withOpacity(
                                  0.5) : Colors.transparent,
                              width: 1.5,
                            ),
                            // 选中时增加一点淡淡的阴影
                            boxShadow: isSelected
                                ? [
                              BoxShadow(color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ]
                                : [],
                          ),
                          child: ListTile(
                            // 这里的圆角要跟 Container 保持一致，点击水波纹才不会出界
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            title: Text(
                              entry.kana.first.written,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: WaColors.sumiBlack,
                              ),
                            ),
                            subtitle: allKanjiText.isNotEmpty
                                ? Text(
                              allKanjiText,
                              style: TextStyle(
                                color: isSelected ? WaColors.akaRed.withOpacity(0.8) : WaColors.sumiBlack.withOpacity(0.5),
                                fontSize: 13,
                              ),
                            )
                                : null,
                            onTap: () async {
                              FocusScope.of(context).unfocus(); // 点击时顺便收起键盘
                              final isCollected = await _vocabService.isCollected(entry.entSeq);
                              setState(() {
                                _selectedEntry = entry;
                                _exampleSentence = ""; // 切换词条时清空例句
                                _isCollected = isCollected;
                              });
                            },
                          ),
                        );
                        // --- 结束 ---
                      },
                    );
                  },
                ),
              )
          ),

          const Divider(thickness: 2, color: Colors.grey),

          // 下半部分：选中的单词详情
          Expanded(
            flex: 3, // 详情占 3 份空间
            child: _selectedEntry == null
                ? const Center(child: Text('请点击列表查看释义'))
                : _buildDetailView(_selectedEntry!),
          ),
        ],
      ),
    );
  }

  // 构建详情展示区域
  Widget _buildDetailView(JmEntry entry) {
    return FutureBuilder<List<JmSense>>(
      future: _dictService.getSensesByEntSeq(entry.entSeq),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final allSenses = snapshot.data ?? [];
        final senses = allSenses.where((s) {
          // 只保留 英文(null/'eng') 和 中文('chi'/'zho')
          // 如果你只想看英文，可以只保留 s.lang == null || s.lang == 'eng'
          return s.lang == null ||
              s.lang == '' ||
              s.lang == 'eng' ||
              s.lang == 'chi' ||
              s.lang == 'zho';
        }).toList();

        return Container(
          color: WaColors.washiPaper, // 细节背景色
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 头部：和风装饰条
              Row(
                children: [
                  Container(width: 4, height: 24, color: WaColors.akaRed),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDetailHeader(entry)),
                ],
              ),
              const SizedBox(height: 8),
              if (entry.kanji.isNotEmpty)
                Text(entry.kana.first.written,
                    style: TextStyle(fontSize: 16,
                        color: WaColors.sumiBlack.withOpacity(0.6),
                        letterSpacing: 1.2)),

              const SizedBox(height: 16),
              
              // 例句生成按钮及展示
              _buildExampleSection(entry),

              const SizedBox(height: 24),

              // 释义部分包裹在 Material 卡片中
              ...senses
                  .asMap()
                  .entries
                  .map((entryItem) {
                final index = entryItem.key + 1;
                final sense = entryItem.value;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 第一行：编号 + 词性标签
                      Row(
                        children: [
                          Text('$index.', style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: WaColors.akaRed)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              children: sense.pos.map((p) =>
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: WaColors.kokeGreen.withOpacity(
                                          0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(JmParser.posToChinese(p),
                                        style: const TextStyle(fontSize: 10,
                                            color: WaColors.kokeGreen,
                                            fontWeight: FontWeight.bold)),
                                  )).toList(),
                            ),
                          ),
                          // 如果是中文释义，显示一个微小的“中”字标签
                          if (sense.lang == 'chi' || sense.lang == 'zho')
                            const Text('中', style: TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 释义内容
                      Text(
                        sense.glosses.join('; '),
                        style: const TextStyle(
                            fontSize: 17,
                            color: WaColors.sumiBlack,
                            height: 1.4,
                            fontWeight: FontWeight.w400
                        ),
                      ),

                      // 备注部分（Note）
                      if (sense.note != null && sense.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 0),
                          child: Text(
                            '※ ${sense.note}',
                            style: TextStyle(fontSize: 12,
                                color: WaColors.sumiBlack.withOpacity(0.5),
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExampleSection(JmEntry entry) {
    String word = entry.kanji.isNotEmpty ? entry.kanji.first.written : entry.kana.first.written;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _isGeneratingExample ? null : () => _generateExample(word),
          icon: _isGeneratingExample 
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome, size: 16),
          label: const Text('生成 AI 例句'),
          style: OutlinedButton.styleFrom(
            foregroundColor: WaColors.akaRed,
            side: const BorderSide(color: WaColors.akaRed),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (_exampleSentence.isNotEmpty || _isGeneratingExample)
          IrisSelectionArea(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WaColors.akaRed.withOpacity(0.1)),
                ),
                child: MarkdownBody(
                  data: _exampleSentence.isEmpty && _isGeneratingExample ? "正在思考例句..." : _exampleSentence,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 14, color: WaColors.sumiBlack, height: 1.5),
                  ),
                ),
              ),
          )
      ],
    );
  }

  Widget _buildDetailHeader(JmEntry entry) {
    // 获取所有汉字写法，并去重合并
    List<String> allKanji = entry.kanji.map((k) => k.written).toList();
    String displayTitle = allKanji.isNotEmpty ? allKanji.join('、') : entry
        .kana.first.written;

    // 获取用于发音的文本（通常取第一个汉字写法，如果没有汉字则取假名）
    String voiceText = allKanji.isNotEmpty ? allKanji.first : entry.kana.first.written;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center, // 垂直居中对齐图标和文字
      spacing: 12, // 文字与按钮的间距
      children: [
        // 标题文字部分
        Wrap(
          children: displayTitle.split('').map((char) {
            if (char == '、') return const Text('、', style: TextStyle(fontSize: 32, color: Colors.grey));
            bool isKanji = RegExp(r'[\u4e00-\u9fa5]').hasMatch(char);
            return GestureDetector(
              onTap: isKanji ? () => _showKanjiDetail(char) : null,
              child: Text(
                char,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isKanji ? WaColors.akaRed : WaColors.sumiBlack,
                  decoration: isKanji ? TextDecoration.underline : TextDecoration.none,
                  decorationStyle: TextDecorationStyle.dashed,
                  decorationColor: WaColors.akaRed.withOpacity(0.5),
                ),
              ),
            );
          }).toList(),
        ),

        // 播放按钮
        IconButton(
          onPressed: () => _ttsService.speak(voiceText, voiceName: "ja-JP-NanamiNeural"),
          icon: const Icon(Icons.volume_up_rounded),
          color: WaColors.akaRed,
          iconSize: 28,
          tooltip: '播放读音',
          style: IconButton.styleFrom(
            backgroundColor: WaColors.akaRed.withOpacity(0.1),
            padding: const EdgeInsets.all(8),
          ),
        ),

        // 收藏按钮
        IconButton(
          onPressed: () => _toggleCollection(entry),
          icon: Icon(_isCollected ? Icons.star : Icons.star_border),
          color: _isCollected ? Colors.orange : Colors.grey,
          iconSize: 28,
          tooltip: _isCollected ? "取消收藏" : "收藏",
          style: IconButton.styleFrom(
            backgroundColor: (_isCollected ? Colors.orange : Colors.grey).withOpacity(0.1),
            padding: const EdgeInsets.all(8),
          ),
        )
      ],
    );
  }

  void _toggleCollection(JmEntry entry) async {
    if (_isCollected) {
      await _vocabService.removeEntry(entry.entSeq);
      setState(() {
        _isCollected = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已从生词本移除')));
      }
    } else {
      _showAddVocabularyDialog(entry);
    }
  }

  void _showAddVocabularyDialog(JmEntry entry) {
    final TextEditingController noteController = TextEditingController();
    final String word = entry.kanji.isNotEmpty ? entry.kanji.first.written : entry.kana.first.written;
    final String kana = entry.kana.first.written;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加到生词本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('单词: $word', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('读音: $kana'),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: '备注 (可选)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newEntry = VocabularyEntry(
                  entSeq: entry.entSeq,
                  word: word,
                  kana: kana,
                  addTime: DateTime.now(),
                  reviewTime: DateTime.now().add(const Duration(days: 1)),
                  note: noteController.text.trim(),
                );
                await _vocabService.addEntry(newEntry);
                if (mounted) {
                  setState(() {
                    _isCollected = true;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加到生词本')));
                }
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }


}

// 和风配色常量 (已移至 lib/utils/wa_colors.dart)
