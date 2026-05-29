import 'package:flutter/material.dart';
import '../custom_component/iris_selection_area.dart';
import 'grammar_model.dart';
import 'package:intl/intl.dart';

class GrammarDetailPage extends StatelessWidget {
  final GrammarEntry entry;

  const GrammarDetailPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文法详情'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: IrisSelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorScheme.primary, colorScheme.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      entry.meaning,
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Structure Section
              if (entry.structure.isNotEmpty) ...[
                _buildSectionTitle(context, Icons.link, '接续结构'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Text(
                    entry.structure,
                    style: textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Examples Section
              if (entry.examples.isNotEmpty) ...[
                _buildSectionTitle(context, Icons.translate, '用法例句'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    entry.examples,
                    style: textTheme.bodyLarge?.copyWith(height: 1.8),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Notes Section
              if (entry.note != null && entry.note!.isNotEmpty) ...[
                _buildSectionTitle(context, Icons.sticky_note_2_outlined, '笔记备注'),
                const SizedBox(height: 12),
                Text(
                  entry.note!,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
              ],

              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.calendar_today, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Text(
                    '收录于 ${DateFormat('yyyy年MM月dd日').format(entry.addTime)}',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        )
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, IconData icon, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
