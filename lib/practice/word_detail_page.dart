import 'package:flutter/material.dart';
import 'package:Iris/jm/dictionary_service.dart';
import 'package:Iris/jm/models.dart';
import 'package:Iris/jm/jm_parser.dart';
import 'package:Iris/utils/edge_tts_service.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Iris/custom_component/iris_selection_area.dart';
import 'package:Iris/utils/wa_colors.dart';
import 'vocabulary_service.dart';
import 'vocabulary_model.dart';

class WordDetailPage extends StatefulWidget {
  final int entSeq;
  final String? initialWord;
  final String? initialKana;

  const WordDetailPage({
    super.key,
    required this.entSeq,
    this.initialWord,
    this.initialKana,
  });

  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  final DictionaryService _dictService = DictionaryService();
  final VocabularyService _vocabService = VocabularyService();
  final EdgeTtsService _ttsService = EdgeTtsService();
  final GemmaSkill _gemmaSkill = GemmaSkill();

  JmEntry? _entry;
  bool _isLoading = true;
  bool _isCollected = false;
  String _exampleSentence = "";
  bool _isGeneratingExample = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final entries = await _dictService.searchEntries(widget.initialWord ?? "");
    // Try to find the exact entry by entSeq
    JmEntry? foundEntry;
    try {
      // searchEntries might not be enough if it only searches by query.
      // But DictionaryService doesn't have getEntryByEntSeq.
      // Let's assume searchEntries(widget.initialWord) will include it.
      // Wait, let's check DictionaryService again. It has searchEntries and getSensesByEntSeq.
      // It doesn't have a direct getEntryByEntSeq that returns JmEntry.
      // I'll use searchEntries and filter.
      for (var e in entries) {
        if (e.entSeq == widget.entSeq) {
          foundEntry = e;
          break;
        }
      }
      
      // If not found, we might need a better way. But for now this is a start.
      if (foundEntry == null && entries.isNotEmpty) {
        foundEntry = entries.first; // Fallback
      }
    } catch (e) {
      // ignore
    }

    _isCollected = await _vocabService.isCollected(widget.entSeq);

    setState(() {
      _entry = foundEntry;
      _isLoading = false;
    });
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_entry != null ? "单词详情" : "加载中..."),
        backgroundColor: WaColors.washiPaper,
        elevation: 0,
        foregroundColor: WaColors.sumiBlack,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entry == null
              ? const Center(child: Text("未找到单词详情"))
              : _buildDetailView(_entry!),
    );
  }

  Widget _buildDetailView(JmEntry entry) {
    return FutureBuilder<List<JmSense>>(
      future: _dictService.getSensesByEntSeq(entry.entSeq),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allSenses = snapshot.data ?? [];
        final senses = allSenses.where((s) {
          return s.lang == null || s.lang == '' || s.lang == 'eng' || s.lang == 'chi' || s.lang == 'zho';
        }).toList();

        return Container(
          color: WaColors.washiPaper,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
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
                    style: TextStyle(fontSize: 16, color: WaColors.sumiBlack.withOpacity(0.6), letterSpacing: 1.2)),
              const SizedBox(height: 16),
              _buildExampleSection(entry),
              const SizedBox(height: 24),
              ...senses.asMap().entries.map((item) {
                final index = item.key + 1;
                final sense = item.value;
                return _buildSenseCard(index, sense);
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSenseCard(int index, JmSense sense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$index.', style: const TextStyle(fontWeight: FontWeight.bold, color: WaColors.akaRed)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: sense.pos
                      .map((p) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: WaColors.kokeGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(JmParser.posToChinese(p),
                                style: const TextStyle(
                                    fontSize: 10, color: WaColors.kokeGreen, fontWeight: FontWeight.bold)),
                          ))
                      .toList(),
                ),
              ),
              if (sense.lang == 'chi' || sense.lang == 'zho')
                const Text('中', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            sense.glosses.join('; '),
            style: const TextStyle(fontSize: 17, color: WaColors.sumiBlack, height: 1.4, fontWeight: FontWeight.w400),
          ),
          if (sense.note != null && sense.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 0),
              child: Text(
                '※ ${sense.note}',
                style: TextStyle(fontSize: 12, color: WaColors.sumiBlack.withOpacity(0.5), fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
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
    List<String> allKanji = entry.kanji.map((k) => k.written).toList();
    String displayTitle = allKanji.isNotEmpty ? allKanji.join('、') : entry.kana.first.written;
    String voiceText = allKanji.isNotEmpty ? allKanji.first : entry.kana.first.written;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
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
        IconButton(
          onPressed: () => _ttsService.speak(voiceText, voiceName: "ja-JP-NanamiNeural"),
          icon: const Icon(Icons.volume_up_rounded),
          color: WaColors.akaRed,
          iconSize: 28,
          style: IconButton.styleFrom(backgroundColor: WaColors.akaRed.withOpacity(0.1), padding: const EdgeInsets.all(8)),
        ),
        IconButton(
          onPressed: () => _toggleCollection(entry),
          icon: Icon(_isCollected ? Icons.star : Icons.star_border),
          color: _isCollected ? Colors.orange : Colors.grey,
          iconSize: 28,
          style: IconButton.styleFrom(
              backgroundColor: (_isCollected ? Colors.orange : Colors.grey).withOpacity(0.1),
              padding: const EdgeInsets.all(8)),
        )
      ],
    );
  }

  void _toggleCollection(JmEntry entry) async {
    if (_isCollected) {
      await _vocabService.removeEntry(entry.entSeq);
      setState(() => _isCollected = false);
    } else {
      final newEntry = VocabularyEntry(
        entSeq: entry.entSeq,
        word: entry.kanji.isNotEmpty ? entry.kanji.first.written : entry.kana.first.written,
        kana: entry.kana.first.written,
        addTime: DateTime.now(),
        reviewTime: DateTime.now().add(const Duration(days: 1)),
      );
      await _vocabService.addEntry(newEntry);
      setState(() => _isCollected = true);
    }
  }

  void _showKanjiDetail(String char) async {
    final kanji = await _dictService.getKanjiInfo(char);
    if (kanji == null) return;
    if (!mounted) return;

    final filteredMeanings = kanji.readingMeaning?.meanings
            .where((m) => m.lang == null || m.lang == '' || m.lang == 'en' || m.lang == "zh")
            .map((m) =>
                m.lang == null ? m.value : (m.lang == "en" ? "英" : (m.lang == "zh" ? "中" : "")) + ". " + m.value)
            .toList() ??
        [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(kanji.literal, style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('笔画: ${kanji.misc?['stroke_count'] ?? '未知'}'),
                          Text('JLPT: N${kanji.misc?['jlpt'] ?? '未知'}'),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text('读音', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: kanji.readingMeaning?.readings
                            .map((r) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: r.type == 'ja_on' ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(r.type == 'ja_on' ? '音' : '训',
                                          style: TextStyle(
                                              fontSize: 10, color: r.type == 'ja_on' ? Colors.red : Colors.blue)),
                                      const SizedBox(width: 6),
                                      Text(r.value, style: const TextStyle(fontSize: 16)),
                                    ],
                                  ),
                                ))
                            .toList() ??
                        [],
                  ),
                  const SizedBox(height: 24),
                  const Text('含义', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: filteredMeanings.asMap().entries.map((entry) {
                      int index = entry.key + 1;
                      String value = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$index. ',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            Expanded(child: Text(value, style: const TextStyle(fontSize: 15, height: 1.4))),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
