import 'package:flutter/material.dart';
import 'package:Iris/jm/dictionary_service.dart';
import 'package:Iris/jm/models.dart';
import 'vocabulary_service.dart';
import 'vocabulary_model.dart';
import 'package:Iris/utils/wa_colors.dart';

class VocabularyFlashcardPage extends StatefulWidget {
  final List<VocabularyEntry> entries;
  const VocabularyFlashcardPage({super.key, required this.entries});

  @override
  State<VocabularyFlashcardPage> createState() => _VocabularyFlashcardPageState();
}

class _VocabularyFlashcardPageState extends State<VocabularyFlashcardPage> {
  final VocabularyService _vocabService = VocabularyService();
  final DictionaryService _dictService = DictionaryService();
  final PageController _pageController = PageController();
  
  int _currentIndex = 0;
  bool _showBack = false;
  List<JmSense> _currentSenses = [];
  bool _loadingSenses = false;

  @override
  void initState() {
    super.initState();
    _loadSenses();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadSenses() async {
    if (_currentIndex >= widget.entries.length) return;
    if (!mounted) return;
    setState(() {
      _loadingSenses = true;
      _showBack = false;
    });
    final senses = await _dictService.getSensesByEntSeq(widget.entries[_currentIndex].entSeq);
    if (!mounted) return;
    setState(() {
      _currentSenses = senses.where((s) => s.lang == null || s.lang == '' || s.lang == 'eng' || s.lang == 'chi' || s.lang == 'zho').toList();
      _loadingSenses = false;
    });
  }

  void _nextCard() {
    if (_currentIndex < widget.entries.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _showFinishedDialog();
    }
  }

  void _showFinishedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('复习完成'),
        content: const Text('你已经完成了本次所有的生词复习！'),
        actions: [
          TextButton(
            onPressed: () {
              // 1. 先关闭对话框 (使用 dialogContext)
              Navigator.of(dialogContext).pop();
              // 2. 再关闭背词页面
              Navigator.of(context).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _rate(int level) async {
    final entry = widget.entries[_currentIndex];
    int newFamiliarity = entry.familiarity;
    int intervalDays = 1;

    switch (level) {
      case 0: // Again
        newFamiliarity = 0;
        intervalDays = 0;
        break;
      case 1: // Hard
        newFamiliarity = (newFamiliarity - 1).clamp(0, 10);
        intervalDays = 1;
        break;
      case 2: // Good
        newFamiliarity = newFamiliarity + 1;
        intervalDays = _getInterval(newFamiliarity);
        break;
      case 3: // Easy
        newFamiliarity = newFamiliarity + 2;
        intervalDays = _getInterval(newFamiliarity);
        break;
    }

    final nextReview = DateTime.now().add(Duration(days: intervalDays));
    await _vocabService.updateFamiliarity(entry.entSeq, newFamiliarity, nextReview);
    if (mounted) _nextCard();
  }

  int _getInterval(int familiarity) {
    if (familiarity <= 0) return 0;
    if (familiarity == 1) return 1;
    if (familiarity == 2) return 3;
    if (familiarity == 3) return 7;
    if (familiarity == 4) return 14;
    if (familiarity == 5) return 30;
    return 60; // Max for now
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return Scaffold(
        backgroundColor: WaColors.washiPaper,
        appBar: AppBar(title: const Text('背词试炼')),
        body: const Center(child: Text('没有需要复习的单词')),
      );
    }

    return Scaffold(
      backgroundColor: WaColors.washiPaper,
      appBar: AppBar(
        title: Text('背词中 (${_currentIndex + 1}/${widget.entries.length})'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: WaColors.sumiBlack,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable manual swipe to force rating
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                _loadSenses();
              },
              itemCount: widget.entries.length,
              itemBuilder: (context, index) {
                final entry = widget.entries[index];
                return _buildCard(entry);
              },
            ),
          ),
          if (_showBack) _buildRatingButtons() else const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildCard(VocabularyEntry entry) {
    return GestureDetector(
      onTap: () {
        if (!_showBack) setState(() => _showBack = true);
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  entry.word,
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: WaColors.akaRed),
                  textAlign: TextAlign.center,
                ),
                if (_showBack) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  Text(
                    entry.kana,
                    style: TextStyle(fontSize: 24, color: WaColors.sumiBlack.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 16),
                  if (_loadingSenses)
                    const CircularProgressIndicator()
                  else
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _currentSenses.length,
                        itemBuilder: (context, index) {
                          final sense = _currentSenses[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '${index + 1}. ${sense.glosses.join("; ")}',
                              style: const TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                ] else ...[
                  const SizedBox(height: 48),
                  Text(
                    '点击查看释义',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRatingButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRateBtn('忘记', Colors.redAccent, 0),
          _buildRateBtn('困难', Colors.orangeAccent, 1),
          _buildRateBtn('良好', Colors.blueAccent, 2),
          _buildRateBtn('简单', Colors.green, 3),
        ],
      ),
    );
  }

  Widget _buildRateBtn(String label, Color color, int level) {
    return ElevatedButton(
      onPressed: () => _rate(level),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}
