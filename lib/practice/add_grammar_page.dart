import 'package:flutter/material.dart';
import 'grammar_model.dart';
import 'grammar_service.dart';

class AddGrammarPage extends StatefulWidget {
  final GrammarEntry? entry; // If provided, we are editing

  const AddGrammarPage({super.key, this.entry});

  @override
  State<AddGrammarPage> createState() => _AddGrammarPageState();
}

class _AddGrammarPageState extends State<AddGrammarPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _meaningController;
  late TextEditingController _structureController;
  late TextEditingController _examplesController;
  late TextEditingController _noteController;
  final GrammarService _grammarService = GrammarService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _meaningController = TextEditingController(text: widget.entry?.meaning ?? '');
    _structureController = TextEditingController(text: widget.entry?.structure ?? '');
    _examplesController = TextEditingController(text: widget.entry?.examples ?? '');
    _noteController = TextEditingController(text: widget.entry?.note ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _meaningController.dispose();
    _structureController.dispose();
    _examplesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final entry = GrammarEntry(
        id: widget.entry?.id,
        title: _titleController.text,
        meaning: _meaningController.text,
        structure: _structureController.text,
        examples: _examplesController.text,
        addTime: widget.entry?.addTime ?? DateTime.now(),
        note: _noteController.text,
      );

      if (widget.entry == null) {
        await _grammarService.addEntry(entry);
      } else {
        await _grammarService.updateEntry(entry);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? '添加文法' : '编辑文法'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '语法条目',
                  hintText: '如：～ことにしている',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty ? '请输入语法条目' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _meaningController,
                decoration: const InputDecoration(
                  labelText: '意义/用法',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator: (value) => value == null || value.isEmpty ? '请输入意义/用法' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _structureController,
                decoration: const InputDecoration(
                  labelText: '接续结构',
                  hintText: '如：动词连体形 + ...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _examplesController,
                decoration: const InputDecoration(
                  labelText: '例句',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
