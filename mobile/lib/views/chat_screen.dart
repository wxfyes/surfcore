import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import 'settings_screen.dart';
import 'video_call_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String _currentLocaleId = 'zh_CN';

  // 豆包风格语音按住说话状态
  bool _isVoiceMode = false; // 是否处于底部按住说话大按钮模式
  bool _isHoldingRecord = false; // 是否当前正按住录音
  bool _isCanceling = false; // 是否上滑进入取消模式
  String _liveWords = ''; // 实时识别文字
  DateTime? _voiceStartTime;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          if (mounted && _isHoldingRecord) {
            setState(() => _isHoldingRecord = false);
          }
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted && _isHoldingRecord) {
              // 保持 holding 状态由松手控制
            }
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

  /// 按下开始录音（豆包模式）
  void _onVoiceStart() async {
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

    HapticFeedback.mediumImpact();
    setState(() {
      _isHoldingRecord = true;
      _isCanceling = false;
      _liveWords = '';
      _voiceStartTime = DateTime.now();
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted || !_isHoldingRecord) return;
          setState(() {
            _liveWords = result.recognizedWords;
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
    } catch (e) {
      debugPrint('[STT] 启动录音异常: $e');
      if (mounted) setState(() => _isHoldingRecord = false);
    }
  }

  /// 手势滑动中：检测上滑取消
  void _onVoiceMove(Offset localPosition) {
    if (!_isHoldingRecord) return;
    // 当手指向上滑动超过 50 像素时判定为上滑取消
    final shouldCancel = localPosition.dy < -50;
    if (shouldCancel != _isCanceling) {
      HapticFeedback.selectionClick();
      setState(() => _isCanceling = shouldCancel);
    }
  }

  /// 松手结束录音并自动发送（豆包模式）
  void _onVoiceEnd() async {
    if (!_isHoldingRecord) return;

    final wasCanceling = _isCanceling;
    final duration = DateTime.now().difference(_voiceStartTime ?? DateTime.now());

    HapticFeedback.lightImpact();
    try {
      await _speech.stop();
    } catch (_) {}

    setState(() {
      _isHoldingRecord = false;
      _isCanceling = false;
    });

    if (!mounted) return;

    // 1. 用户主动上滑取消
    if (wasCanceling) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已取消发送'),
          duration: Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 2. 录音时间太短（小于 500ms）
    if (duration.inMilliseconds < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('说话时间太短'),
          duration: Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 稍等 150ms 确保语音引擎最后一段文本刷回
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final textToSend = _liveWords.trim();
    if (textToSend.isNotEmpty) {
      final provider = context.read<ChatProvider>();
      provider.sendMessage(textToSend);
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未听清，请按住重说一次哦～'),
          duration: Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
          // 豆包同款语音播报开关（开启才请求火山TTS，关闭省额度）
          IconButton(
            icon: Icon(
              provider.isVoiceReplyEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: provider.isVoiceReplyEnabled ? const Color(0xFF8B5CF6) : Colors.grey,
            ),
            tooltip: provider.isVoiceReplyEnabled ? '语音播报: 已开启 (调用火山TTS)' : '语音播报: 已关闭 (省额度)',
            onPressed: () {
              HapticFeedback.mediumImpact();
              final willEnable = !provider.isVoiceReplyEnabled;
              provider.toggleVoiceReply();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    willEnable
                        ? '🎙️ 已开启小娘子语音播放（调用火山引擎合成）'
                        : '🔇 已关闭语音播放（纯文本回复，不消耗火山额度）',
                  ),
                  duration: const Duration(milliseconds: 1500),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          // 📹 闺房视讯·视频通话
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Color(0xFF8B5CF6)),
            tooltip: '发起闺房视频通话',
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VideoCallScreen()),
              );
            },
          ),
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
        child: Stack(
          children: [
            Column(
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

            // 豆包风格屏幕中央按住说话悬浮弹窗
            if (_isHoldingRecord) _buildVoiceHoldingModal(),
          ],
        ),
      ),
    );
  }

  /// 豆包风格高颜值录音悬浮窗
  Widget _buildVoiceHoldingModal() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 220,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color: _isCanceling ? const Color(0xFFEF4444) : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCanceling
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    _isCanceling ? Icons.delete_outline_rounded : Icons.mic_rounded,
                    size: 38,
                    color: _isCanceling ? Colors.white : const Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _isCanceling
                      ? '松开手指，取消发送'
                      : (_liveWords.isEmpty ? '正在倾听中...' : _liveWords),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _isCanceling ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isCanceling
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isCanceling ? '松开取消' : '松开发送，上滑取消',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isCanceling ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      child: Row(
        children: [
          // 左侧：切换“按住说话”模式与“打字”模式
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isVoiceMode = !_isVoiceMode;
              });
            },
            icon: Icon(
              _isVoiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none_rounded,
              color: const Color(0xFF8B5CF6),
              size: 26,
            ),
            tooltip: _isVoiceMode ? '切换打字' : '切换按住说话',
          ),
          const SizedBox(width: 4),

          // 中间区域：按住说话大按钮 OR 文本输入框
          Expanded(
            child: _isVoiceMode
                ? GestureDetector(
                    onLongPressStart: (_) => _onVoiceStart(),
                    onLongPressMoveUpdate: (d) => _onVoiceMove(d.localPosition),
                    onLongPressEnd: (_) => _onVoiceEnd(),
                    onVerticalDragStart: (_) => _onVoiceStart(),
                    onVerticalDragUpdate: (d) => _onVoiceMove(d.localPosition),
                    onVerticalDragEnd: (_) => _onVoiceEnd(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: _isHoldingRecord
                            ? const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)])
                            : null,
                        color: _isHoldingRecord ? null : Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _isHoldingRecord
                              ? const Color(0xFF8B5CF6)
                              : Colors.grey.withValues(alpha: 0.25),
                          width: 1.2,
                        ),
                        boxShadow: _isHoldingRecord
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isHoldingRecord ? Icons.mic : Icons.mic_rounded,
                            size: 20,
                            color: _isHoldingRecord ? Colors.white : const Color(0xFF8B5CF6),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isHoldingRecord ? '松开 发送' : '按住 说话',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _isHoldingRecord ? Colors.white : Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(
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
                      decoration: const InputDecoration(
                        hintText: '发消息，或点左侧切换按住说话...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),

          // 右侧：打字发送按钮
          IconButton.filled(
            onPressed: provider.isSending ? null : _handleSend,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              shape: const CircleBorder(),
            ),
            icon: provider.isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

