import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server_config.dart';
import '../providers/chat_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  bool _useHttps = false;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ChatProvider>();
    _hostController = TextEditingController(text: provider.config.host);
    _portController = TextEditingController(text: provider.config.port.toString());
    _tokenController = TextEditingController(text: provider.config.token);
    _useHttps = provider.config.useHttps;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _handleTestConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    final tempConfig = ServerConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 3080,
      token: _tokenController.text.trim(),
      useHttps: _useHttps,
    );

    final provider = context.read<ChatProvider>();
    final ok = await provider.saveConfig(tempConfig);

    setState(() {
      _isTesting = false;
      _testSuccess = ok;
      if (ok) {
        _testResult = '连接成功！当前搭档：${provider.petStatus.characterName} (${provider.petStatus.presenceState})';
      } else {
        _testResult = '连接失败！请确认小主机服务已启动、IP与Token无误。';
      }
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    final tempConfig = ServerConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 3080,
      token: _tokenController.text.trim(),
      useHttps: _useHttps,
    );

    final provider = context.read<ChatProvider>();
    await provider.saveConfig(tempConfig);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存并同步')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器连接设置'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF2563EB)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '局域网可填小主机内网 IP (如 192.168.1.213)；外网可填 Tailscale IP。Token 可在小主机设置页一键获取。',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '小主机 IP 或域名',
                  hintText: '192.168.1.213 或 100.x.x.x',
                  prefixIcon: Icon(Icons.dns_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? '请输入主机 IP' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口 (Port)',
                  hintText: '3080',
                  prefixIcon: Icon(Icons.numbers_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                validator: (val) {
                  final p = int.tryParse(val ?? '');
                  if (p == null || p <= 0 || p > 65535) return '请输入有效端口 (1-65535)';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: '通信令牌 (Pet Token)',
                  hintText: '粘贴桌宠令牌',
                  prefixIcon: Icon(Icons.key_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 HTTPS (SSL)'),
                subtitle: const Text('局域网直连或 Tailscale 请保持关闭'),
                value: _useHttps,
                onChanged: (val) => setState(() => _useHttps = val),
              ),
              const SizedBox(height: 20),
              if (_testResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testSuccess == true ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testSuccess == true ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess == true ? Icons.check_circle : Icons.error_outline,
                        color: _testSuccess == true ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testSuccess == true ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: _isTesting ? null : _handleTestConnection,
                icon: _isTesting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: Text(_isTesting ? '正在探测连通性...' : '一键测试连接'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _handleSave,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('保存配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 32),
              const Divider(),
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('确认清空历史？'),
                      content: const Text('将清空手机端本地保存的所有对话历史。'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('清空', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await context.read<ChatProvider>().clearHistory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('聊天历史已清空')));
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('清空本地聊天记录', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
