import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_gemma/flutter_gemma.dart';

class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({super.key});

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage> {
  List<File> _models = [];
  bool _isImporting = false;
  
  // Try Now state
  File? _selectedModelForTest;
  String _generatedResponse = "";
  bool _isGenerating = false;
  final TextEditingController _questionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    final directory = await getApplicationDocumentsDirectory();
    final modelDir = Directory(p.join(directory.path, 'models'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final files = modelDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.litertlm'))
        .toList();

    setState(() {
      _models = files;
      if (_models.isNotEmpty && _selectedModelForTest == null) {
        _selectedModelForTest = _models.first;
      }
    });
  }

  Future<void> _importModel() async {
    setState(() => _isImporting = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        if (!filePath.endsWith('.litertlm')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('只支持 .litertlm 格式的模型文件'), backgroundColor: Colors.orange),
            );
          }
          return;
        }

        final sourceFile = File(filePath);
        final directory = await getApplicationDocumentsDirectory();
        final fileName = p.basename(filePath);
        final targetPath = p.join(directory.path, 'models', fileName);

        await sourceFile.copy(targetPath);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('模型 $fileName 导入成功')),
          );
        }
        _loadModels();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _deleteModel(File file) async {
    try {
      await file.delete();
      if (_selectedModelForTest?.path == file.path) {
        _selectedModelForTest = null;
      }
      _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模型已删除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleTryNow() async {
    if (_selectedModelForTest == null || _questionController.text.isEmpty) return;

    setState(() {
      _generatedResponse = "";
      _isGenerating = true;
    });

    try {
      print("开始加载");
      // 1. Install model from file
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(_selectedModelForTest!.path)
          .install();
      print("安装模型完成");
      // 2. Get active model and create chat
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu
      );
      print("获取到模型");
      final chat = await model.createChat();

      // 3. Add user query
      await chat.addQueryChunk(Message.text(text: _questionController.text, isUser: true));

      // 4. Listen to stream
      final stream = chat.generateChatResponseAsync();
      
      await for (final response in stream) {
        if (response is TextResponse) {
          setState(() {
            _generatedResponse += response.token;
          });
        }
      }

      chat.close();
    } catch (e) {
      print(e);
      setState(() {
        _generatedResponse = "发生错误: $e";
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('模型设置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(colorScheme),
            if (_models.isNotEmpty) _buildTryNowPanel(colorScheme, isDark),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Divider(),
            ),
            _models.isEmpty
                ? SizedBox(
                    height: 300,
                    child: _buildEmptyState(colorScheme),
                  )
                : _buildModelList(colorScheme, isDark),
            const SizedBox(height: 100), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _importModel,
        icon: _isImporting 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_rounded),
        label: Text(_isImporting ? '导入中...' : '添加模型'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primaryContainer.withOpacity(0.5), colorScheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.model_training_rounded, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                '本地模型库',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '管理您的 .litertlm 离线大模型。',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTryNowPanel(ColorScheme colorScheme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.secondary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.secondary.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '马上尝试',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              DropdownButton<File>(
                value: _selectedModelForTest,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(12),
                items: _models.map((file) {
                  return DropdownMenuItem<File>(
                    value: file,
                    child: Text(
                      p.basename(file.path),
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: _isGenerating ? null : (File? value) {
                  setState(() => _selectedModelForTest = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _questionController,
            enabled: !_isGenerating,
            decoration: InputDecoration(
              hintText: '问个问题吧...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: Icon(_isGenerating ? Icons.stop_circle : Icons.send_rounded),
                onPressed: _isGenerating ? null : _handleTryNow,
              ),
            ),
          ),
          if (_generatedResponse.isNotEmpty || _isGenerating) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('模型回答', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_generatedResponse.isEmpty && _isGenerating ? "正在思考..." : _generatedResponse),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 80, color: colorScheme.primary.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            '暂无已添加的模型',
            style: TextStyle(fontSize: 18, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildModelList(ColorScheme colorScheme, bool isDark) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _models.length,
      itemBuilder: (context, index) {
        final file = _models[index];
        final fileName = p.basename(file.path);
        final fileSize = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(2);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Icon(Icons.description_rounded, color: colorScheme.primary),
            title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$fileSize MB'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: () => _showDeleteDialog(file),
            ),
          ),
        );
      },
    );
  }

  void _showDeleteDialog(File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除模型 ${p.basename(file.path)} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteModel(file);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
