import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Iris/utils/gemma_skill.dart';
import 'vision_common.dart';

class RecognizeObjectPage extends StatefulWidget {
  const RecognizeObjectPage({super.key});

  @override
  State<RecognizeObjectPage> createState() => _RecognizeObjectPageState();
}

class _RecognizeObjectPageState extends VisionBaseState<RecognizeObjectPage> {
  final GemmaSkill _gemmaSkill = GemmaSkill();
  
  List<String> _recognizedItems = [];
  final Map<String, String> _itemCultures = {};
  final Set<String> _checkedItems = {};
  final Set<String> _completedItems = {};
  String? _activeItem;
  bool _isResolving = false;

  @override
  void dispose() {
    _gemmaSkill.close();
    super.dispose();
  }

  @override
  void reset() {
    super.reset();
    setState(() {
      _recognizedItems = [];
      _itemCultures.clear();
      _checkedItems.clear();
      _completedItems.clear();
      _activeItem = null;
      _isResolving = false;
    });
  }

  Future<void> _startRecognition() async {
    if (imageBytes == null) return;

    setState(() {
      visionState = VisionState.processing;
      resultText = "";
      _recognizedItems = [];
      _itemCultures.clear();
      _checkedItems.clear();
      _completedItems.clear();
      _activeItem = null;
    });

    try {
      await _gemmaSkill.initialize(
        enableVision: true,
      );

      final stream = _gemmaSkill.recognizeObject(imageBytes: imageBytes!);
      await for (final chunk in stream) {
        setState(() {
          resultText += chunk;
        });
      }

      _parseItems();

      setState(() {
        visionState = VisionState.result;
      });
    } catch (e) {
      setState(() {
        resultText = "识别出错: $e";
        visionState = VisionState.result;
      });
    }
  }

  void _parseItems() {
    if (resultText.isEmpty) return;
    final rawItems = resultText.split(RegExp(r'[,，]'));
    _recognizedItems = rawItems
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    
    if (_recognizedItems.isNotEmpty) {
      _activeItem = _recognizedItems.first;
    }
  }

  Future<void> _executeResolving() async {
    if (_checkedItems.isEmpty || _isResolving) return;

    setState(() {
      _isResolving = true;
    });

    // 复制一份待解析列表，防止在循环中被修改
    final itemsToResolve = _checkedItems.toList();

    for (final item in itemsToResolve) {
      if (_completedItems.contains(item)) continue;
      
      // 串行调用解析
      await _resolveCultureInternal(item);
      
      setState(() {
        _completedItems.add(item);
        _checkedItems.remove(item);
      });
    }

    setState(() {
      _isResolving = false;
    });
  }

  Future<void> _resolveCultureInternal(String item) async {
    setState(() {
      _itemCultures[item] = "";
    });

    try {
      final stream = _gemmaSkill.cultureResolve(res: item);
      await for (final chunk in stream) {
        if (mounted) {
          setState(() {
            _itemCultures[item] = (_itemCultures[item] ?? "") + chunk;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _itemCultures[item] = "解析失败: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('看图识物', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildBody(colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    switch (visionState) {
      case VisionState.initial:
        return buildInitialView(
          title: '准备识别物品',
          description: '点击下方按钮拍照或从相册选择图片\nAI 将为您自动识别其中的主要物品并解析其文化内涵',
          icon: Icons.image_search_outlined,
          colorScheme: colorScheme,
        );
      case VisionState.selected:
        return buildSelectedView(
          colorScheme: colorScheme,
          onConfirm: _startRecognition,
        );
      case VisionState.processing:
        return buildProcessingView(
          message: '正在识别图片中的物品...',
          colorScheme: colorScheme,
        );
      case VisionState.result:
        return _buildResultView(colorScheme);
    }
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Hero(
            tag: 'selected_image',
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              child: Image.file(
                imageFile!,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_recognizedItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('识别到的物品 (勾选后点击解析按钮)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  SizedBox(
                    height: 50,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recognizedItems.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = _recognizedItems[index];
                        final isSelected = _activeItem == item;
                        final isChecked = _checkedItems.contains(item);
                        final isCompleted = _completedItems.contains(item);
                        
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isCompleted)
                              Checkbox(
                                value: isChecked,
                                visualDensity: VisualDensity.compact,
                                onChanged: _isResolving ? null : (val) {
                                  setState(() {
                                    if (val == true) {
                                      _checkedItems.add(item);
                                    } else {
                                      _checkedItems.remove(item);
                                    }
                                  });
                                },
                              ),
                            ChoiceChip(
                              label: Text(item),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _activeItem = item);
                                }
                              },
                              backgroundColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                              selectedColor: colorScheme.primaryContainer,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_checkedItems.isEmpty || _isResolving) ? null : _executeResolving,
                      icon: _isResolving 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.psychology_rounded),
                      label: Text(_isResolving ? "正在解析..." : "执行文化背景解析"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (_activeItem != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('$_activeItem · 文化背景', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_completedItems.contains(_activeItem))
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!_completedItems.contains(_activeItem) && !(_isResolving && _checkedItems.contains(_activeItem)))
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Icon(Icons.help_outline_rounded, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.3)),
                            const SizedBox(height: 12),
                            const Text('请勾选该物品并点击“执行文化背景解析”', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else if (_itemCultures[_activeItem] == null || (_itemCultures[_activeItem]!.isEmpty && _isResolving))
                    const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
                  else
                    MarkdownBody(
                      data: _itemCultures[_activeItem]!,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(fontSize: 16, height: 1.6, color: colorScheme.onSurface),
                      ),
                    ),
                ],
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isResolving ? null : reset,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('再拍一张'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
