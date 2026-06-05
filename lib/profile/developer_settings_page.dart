import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Iris/iris_assistant/mascot_controller.dart';

class DeveloperSettingsPage extends StatefulWidget {
  const DeveloperSettingsPage({super.key});

  @override
  State<DeveloperSettingsPage> createState() => _DeveloperSettingsPageState();
}

class _DeveloperSettingsPageState extends State<DeveloperSettingsPage> {
  final MascotController _controller = MascotController();

  final Map<int, String> _tokenOptions = {
    1024: '1K',
    2048: '2K',
    4096: '4K',
    8192: '8K',
    16384: '16K',
    32768: '32K',
    65536: '64K',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('开发者选项'),
          ),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services),
                title: const Text('清除小知识今日记录'),
                subtitle: const Text('清除后可重新生成今日小知识'),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('daily_tip_date');
                  await prefs.remove('daily_tip_content');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('清除成功')),
                    );
                  }
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '模型性能设置',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.toll_rounded),
                title: const Text('Max Tokens (上下文容量)'),
                subtitle: Text('当前设置: ${_tokenOptions[_controller.maxTokens] ?? _controller.maxTokens.toString()}'),
                trailing: DropdownButton<int>(
                  value: _tokenOptions.containsKey(_controller.maxTokens) ? _controller.maxTokens : 8192,
                  items: _tokenOptions.entries.map((entry) {
                    return DropdownMenuItem<int>(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _controller.setMaxTokens(value);
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator()),
                    );
                    await _controller.reloadModel();
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('模型已应用新配置并重新加载')),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('应用设置并重新加载模型'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
