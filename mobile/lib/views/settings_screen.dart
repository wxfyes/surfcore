import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server_config.dart';
import '../providers/chat_provider.dart';

import '../models/routine_config.dart';

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

  // 闺房作息守护状态
  late bool _morningCallEnabled;
  late TimeOfDay _morningCallTime;
  late bool _nightSleepEnabled;
  late TimeOfDay _nightSleepTime;
  late bool _idleChatEnabled;
  late int _idleChatIntervalHours;
  late bool _voiceEnabled;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ChatProvider>();
    _hostController = TextEditingController(text: provider.config.host);
    _portController = TextEditingController(text: provider.config.port.toString());
    _tokenController = TextEditingController(text: provider.config.token);
    _useHttps = provider.config.useHttps;

    final routine = provider.routineConfig;
    _morningCallEnabled = routine.morningCallEnabled;
    final morningParts = routine.morningCallTime.split(':');
    _morningCallTime = TimeOfDay(
      hour: int.tryParse(morningParts.first) ?? 8,
      minute: int.tryParse(morningParts.length > 1 ? morningParts[1] : '0') ?? 0,
    );

    _nightSleepEnabled = routine.nightSleepEnabled;
    final nightParts = routine.nightSleepTime.split(':');
    _nightSleepTime = TimeOfDay(
      hour: int.tryParse(nightParts.first) ?? 23,
      minute: int.tryParse(nightParts.length > 1 ? nightParts[1] : '30') ?? 30,
    );

    _idleChatEnabled = routine.idleChatEnabled;
    _idleChatIntervalHours = routine.idleChatIntervalHours;
    _voiceEnabled = routine.voiceEnabled;
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

    String pad(int n) => n.toString().padLeft(2, '0');
    final newRoutine = RoutineConfig(
      morningCallEnabled: _morningCallEnabled,
      morningCallTime: '${pad(_morningCallTime.hour)}:${pad(_morningCallTime.minute)}',
      nightSleepEnabled: _nightSleepEnabled,
      nightSleepTime: '${pad(_nightSleepTime.hour)}:${pad(_nightSleepTime.minute)}',
      idleChatEnabled: _idleChatEnabled,
      idleChatIntervalHours: _idleChatIntervalHours,
      voiceEnabled: _voiceEnabled,
    );
    await provider.saveRoutineConfig(newRoutine);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('作息守护与服务器配置已保存并同步')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('伴侣作息与连接设置'),
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
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bedtime_rounded, color: Color(0xFF8B5CF6)),
                          SizedBox(width: 8),
                          Text(
                            '闺房作息守护与主动关怀',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '无需开启小主机桌面桌宠！小主机与手机双向心跳守护，锁屏到点准时唤醒。',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Divider(height: 24),
                      // 1. 晨光早安叫醒
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('🌅 晨光早安唤醒', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('早晨 ${_morningCallTime.format(context)} 娇滴滴念语音叫醒夫君'),
                        value: _morningCallEnabled,
                        onChanged: (val) => setState(() => _morningCallEnabled = val),
                        secondary: TextButton(
                          onPressed: _morningCallEnabled
                              ? () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _morningCallTime,
                                  );
                                  if (picked != null) setState(() => _morningCallTime = picked);
                                }
                              : null,
                          child: Text(_morningCallTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      // 2. 深夜催歇就寝
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('🌙 深夜催歇就寝', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('夜晚 ${_nightSleepTime.format(context)} 催促相公放下手机温存安歇'),
                        value: _nightSleepEnabled,
                        onChanged: (val) => setState(() => _nightSleepEnabled = val),
                        secondary: TextButton(
                          onPressed: _nightSleepEnabled
                              ? () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _nightSleepTime,
                                  );
                                  if (picked != null) setState(() => _nightSleepTime = picked);
                                }
                              : null,
                          child: Text(_nightSleepTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      // 3. 白天相思搭话
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('💬 白日主动撒娇', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('白天超过 $_idleChatIntervalHours 小时没理她，主动发情话贴贴'),
                        value: _idleChatEnabled,
                        onChanged: (val) => setState(() => _idleChatEnabled = val),
                        secondary: DropdownButton<int>(
                          value: _idleChatIntervalHours,
                          underline: const SizedBox(),
                          items: [1, 2, 3, 4, 6].map((h) => DropdownMenuItem(value: h, child: Text('$h小时'))).toList(),
                          onChanged: _idleChatEnabled ? (val) => setState(() => _idleChatIntervalHours = val ?? 3) : null,
                        ),
                      ),
                      // 4. 自动语音播报
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('🔊 叫醒时自动朗读语音', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('触发早安/晚安时，手机自动念出小娘子原声语音'),
                        value: _voiceEnabled,
                        onChanged: (val) => setState(() => _voiceEnabled = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
