import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  String _currentLocaleId = 'zh_CN';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (_speechAvailable) {
        try {
          final systemLocale = await _speech.systemLocale();
          final locales = await _speech.locales();
          // 优先寻找包含 zh 的中文普通话语言模型（如 zh_CN, zh-CN, zh-Hans 等）
          stt.LocaleName? targetLocale;
          for (final loc in locales) {
            final id = loc.localeId.toLowerCase().replaceAll('_', '-');
            if (id.startsWith('zh-cn') || id == 'zh-hans' || id == 'zh') {
              targetLocale = loc;
              break;
            }
          }
          targetLocale ??= locales.cast<stt.LocaleName?>().firstWhere(
            (loc) => loc?.localeId.toLowerCase().startsWith('zh') ?? false,
            orElse: () => null,
          );
          if (targetLocale != null) {
            _currentLocaleId = targetLocale.localeId;
          } else if (systemLocale != null && systemLocale.localeId.toLowerCase().startsWith('zh')) {
            _currentLocaleId = systemLocale.localeId;
          } else {
            _currentLocaleId = 'zh_CN';
          }
          debugPrint('[STT] 语音识别就绪，选定中文模型: $_currentLocaleId');
        } catch (e) {
          debugPrint('[STT] 获取语言模型失败，保底 zh_CN: $e');
          _currentLocaleId = 'zh_CN';
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      _speechAvailable = false;
    }
  }

  void _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在初始化语音识别引擎，请确保已授予录音权限...'),
          duration: Duration(seconds: 2),
        ),
      );
      _initSpeech();
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      if (mounted) setState(() => _isListening = true);
      try {
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _textController.text = result.recognizedWords;
              _textController.selection = TextSelection.fromPosition(
                TextPosition(offset: _textController.text.length),
              );
            });
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            cancelOnError: false,
            partialResults: true,
            autoPunctuation: true,
            localeId: _currentLocaleId,
          ),
        );
      } catch (_) {
        if (mounted) setState(() => _isListening = false);
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final provider = context.read<ChatProvider>();
    _textController.clear();
    provider.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isOnline = provider.isConnected;
    final characterName = provider.petStatus.characterName;
    final statusText = isOnline ? provider.petStatus.presenceState : '离线中';

    // 监听消息变化自动滚到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.messages.isNotEmpty) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 16),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF8B5CF6),
                  radius: 19,
                  child: Text(
                    characterName.isNotEmpty ? characterName.characters.first : 'A',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF22C55E) : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    characterName,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isOnline ? const Color(0xFF16A34A) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '服务器配置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!isOnline && provider.isInitialized)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFFEF2F2),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_off, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '未连接到小主机服务器，点击前往配置 IP 与 Token',
                          style: TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Color(0xFF991B1B), size: 18),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: provider.messages.isEmpty
                  ? _buildEmptyState(characterName)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: provider.messages.length,
                      itemBuilder: (context, index) {
                        final msg = provider.messages[index];
                        return MessageBubble(
                          message: msg,
                          characterName: characterName,
                        );
                      },
                    ),
            ),
            _buildInputArea(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String name) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.auto_awesome, size: 48, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(height: 18),
            Text(
              '你的赛博伴侣「$name」已就位',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '已打通记忆卡、作息节律与独立通信通道。\n发句问候开启对话吧～',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isListening)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE11D48)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '🎙️ 正在倾听... 请说话，为您实时打字',
                      style: TextStyle(fontSize: 13, color: Color(0xFFBE123C), fontWeight: FontWeight.w500),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleListening,
                    child: const Text('完成', style: TextStyle(fontSize: 13, color: Color(0xFFE11D48), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: _toggleListening,
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none_rounded,
                  color: _isListening ? const Color(0xFFE11D48) : const Color(0xFF2563EB),
                ),
                tooltip: _isListening ? '点击结束语音' : '语音输入（我说他写）',
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    decoration: InputDecoration(
                      hintText: _isListening ? '正在倾听...' : '发消息或点麦克风说话...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: provider.isSending ? null : _handleSend,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: const CircleBorder(),
                ),
                icon: provider.isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
