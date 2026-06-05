import 'package:flutter/material.dart';
import 'vocabulary_service.dart';
import 'vocabulary_model.dart';
import 'practice_database.dart';
import 'package:intl/intl.dart';
import 'word_detail_page.dart';
import 'vocabulary_flashcard_page.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';

class VocabularyListPage extends StatefulWidget {
  const VocabularyListPage({super.key});

  @override
  State<VocabularyListPage> createState() => _VocabularyListPageState();
}

class _VocabularyListPageState extends State<VocabularyListPage> {
  final VocabularyService _vocabService = VocabularyService();
  List<VocabularyEntry> _entries = [];
  bool _isLoading = true;
  bool _isImporting = false;
  int _newWordsLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadEntries();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _newWordsLimit = prefs.getInt('newWordsLimit') ?? 10;
    });
  }

  Future<void> _saveSettings(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('newWordsLimit', limit);
    setState(() {
      _newWordsLimit = limit;
    });
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    await _vocabService.init();
    final entries = await _vocabService.getAllEntries();
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _resetProgress() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置进度'),
        content: const Text('确定要重置所有单词的复习进度吗？这将把所有单词设为“从未学习”。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _vocabService.resetAllProgress();
      _loadEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('复习进度已重置')));
      }
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final dbPath = await _vocabService.getDatabasePath();
      final dbFile = File(dbPath);
      
      Directory? exportDir;
      if (Platform.isAndroid) {
        exportDir = Directory('/storage/emulated/0/Download');
        if (!await exportDir.exists()) {
          exportDir = await getExternalStorageDirectory();
        }
      } else {
        exportDir = await getDownloadsDirectory();
      }

      if (exportDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取导出目录')));
        }
        return;
      }

      final fileName = "practice_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.sqlite";
      final exportPath = "${exportDir.path}/$fileName";
      await dbFile.copy(exportPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('数据库已成功导出到下载目录'), action: SnackBarAction(label: '查看路径', onPressed: () {
          showDialog(context: context, builder: (context) => AlertDialog(title: const Text('导出路径'), content: SelectableText(exportPath)));
        })));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _importDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        
        setState(() => _isImporting = true);

        // 使用事务和批量处理优化导入速度
        final counts = await PracticeDatabase().importData(path);
        
        if (mounted) {
          await _loadEntries(); // 重新加载数据
          setState(() => _isImporting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入完成：新增 ${counts['vocabulary']} 条生词，${counts['grammar']} 条文法')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  Future<void> _startReview() async {
    final dueEntries = await _vocabService.getDueEntries();
    final newEntries = await _vocabService.getNewEntries(_newWordsLimit);
    
    final allEntries = [...dueEntries, ...newEntries];

    if (allEntries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无需要复习或学习的生词')));
      }
      return;
    }
    
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => VocabularyFlashcardPage(entries: allEntries)),
      );
      _loadEntries();
    }
  }

  void _showSettingsDialog() {
    int tempLimit = _newWordsLimit;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('背词设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('每日新词最大数量:'),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setDialogState) => Column(
                children: [
                  Slider(
                    value: tempLimit.toDouble(),
                    min: 5,
                    max: 50,
                    divisions: 9,
                    label: tempLimit.toString(),
                    onChanged: (v) => setDialogState(() => tempLimit = v.toInt()),
                  ),
                  Text('$tempLimit 个', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              _saveSettings(tempLimit);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('生词本'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '背词设置',
                onPressed: _showSettingsDialog,
              ),
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: '重置所有进度',
                onPressed: _resetProgress,
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: '导入数据库 (追加)',
                onPressed: _isImporting ? null : _importDatabase,
              ),
              IconButton(
                icon: const Icon(Icons.upload),
                tooltip: '导出数据库',
                onPressed: _exportDatabase,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadEntries,
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_entries.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton.icon(
                          onPressed: _startReview,
                          icon: const Icon(Icons.play_arrow),
                          label: Text('开始背词试炼 (${_newWordsLimit}新词+复习)'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _entries.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              itemCount: _entries.length,
                              itemBuilder: (context, index) {
                                final entry = _entries[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: ListTile(
                                    title: Text(entry.word, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(entry.kana),
                                        if (entry.note != null && entry.note!.isNotEmpty)
                                          Text('备注: ${entry.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '熟练度: ${entry.familiarity}',
                                              style: TextStyle(fontSize: 12, color: Colors.blueGrey[700]),
                                            ),
                                            Text(
                                              '添加于: ${DateFormat('yyyy-MM-dd HH:mm').format(entry.addTime)}',
                                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () async {
                                        await _vocabService.removeEntry(entry.entSeq);
                                        _loadEntries();
                                      },
                                    ),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => WordDetailPage(
                                            entSeq: entry.entSeq,
                                            initialWord: entry.word,
                                            initialKana: entry.kana,
                                          ),
                                        ),
                                      );
                                      _loadEntries();
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
        if (_isImporting)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在导入并合并数据...', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('这可能需要一点时间，请稍候', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '生词本还是空的',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          const Text('在搜索详情页点击收藏即可添加'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('去搜索生词'),
          ),
        ],
      ),
    );
  }
}
