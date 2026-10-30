import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';
import '../models/chat_message.dart';
import '../models/pet_status.dart';
import '../models/routine_config.dart';
import '../services/api_client.dart';

class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _prefKeyConfig = 'surfcore_server_config';
  static const String _prefKeyMessages = 'surfcore_chat_history';
  static const String _prefKeyVoiceReply = 'surfcore_voice_reply_enabled';
  static const String _prefKeyRoutine = 'surfcore_routine_config';

  late ServerConfig _config;
  late SurfCoreApiClient _apiClient;
  List<ChatMessage> _messages = [];
  PetStatus _petStatus = PetStatus(online: false);
  bool _isConnected = false;
  bool _isSending = false;
  bool _isInitialized = false;
  bool _pollingActive = false;
  int? _lastEventSeq;

  // 闺房作息守护与主动关怀配置
  RoutineConfig _routineConfig = const RoutineConfig();
  RoutineConfig get routineConfig => _routineConfig;
  Timer? _localRoutineTimer;
  String _lastLocalMorningDate = '';
  String _lastLocalNightDate = '';

  // 豆包风格语音播放开关与主力播放器
  bool _isVoiceReplyEnabled = false; // 默认关闭日常对话语音，让用户右上角自由开启（省火山额度）
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentPlayingUrl;
  String? _nextQueuedMusicUrl;
  bool _isPlayingAudio = false;

  // 锁屏防休眠专职后台静音守护器（维持 iOS / Android 后台 AudioSession，防止锁屏冻结网络与Timer）
  final AudioPlayer _keeperPlayer = AudioPlayer();
  bool _isKeeperActive = false;

  Timer? _statusTimer;

  ServerConfig get config => _config;
  List<ChatMessage> get messages => _messages;
  PetStatus get petStatus => _petStatus;
  bool get isConnected => _isConnected;
  bool get isSending => _isSending;
  bool get isInitialized => _isInitialized;
  bool get isVoiceReplyEnabled => _isVoiceReplyEnabled;
  bool get isPlayingAudio => _isPlayingAudio;
  String? get currentPlayingUrl => _currentPlayingUrl;

  ChatProvider() {
    _config = const ServerConfig(host: '192.168.1.213', port: 3088, token: '');
    _apiClient = SurfCoreApiClient(_config);
    _init();
  }

  Uint8List _createSilentWav({int durationSec = 3, int sampleRate = 8000}) {
    final numChannels = 1;
    final bytesPerSample = 2; // 16-bit PCM
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final dataSize = durationSec * byteRate;
    final totalSize = 44 + dataSize;
    final bytes = Uint8List(totalSize);
    final byteData = ByteData.view(bytes.buffer);

    // 'RIFF'
    bytes.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]);
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    // 'WAVE'
    bytes.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]);
    // 'fmt '
    bytes.setRange(12, 16, [0x66, 0x6D, 0x74, 0x20]);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bytesPerSample * 8, Endian.little);
    // 'data'
    bytes.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]);
    byteData.setUint32(40, dataSize, Endian.little);

    return bytes;
  }

  Future<void> _updateKeeperState() async {
    if (!_routineConfig.keepAliveEnabled) {
      if (_isKeeperActive) {
        try {
          await _keeperPlayer.stop();
        } catch (_) {}
        _isKeeperActive = false;
      }
      return;
    }

    if (_isPlayingAudio) {
      if (_isKeeperActive) {
        try {
          await _keeperPlayer.pause();
        } catch (_) {}
      }
      return;
    }

    try {
      if (!_isKeeperActive) {
        await _keeperPlayer.setReleaseMode(ReleaseMode.loop);
        await _keeperPlayer.setVolume(0.01);
        await _keeperPlayer.play(BytesSource(_createSilentWav()));
        _isKeeperActive = true;
        debugPrint('[KeepAlive] 锁屏夜间守护静音心跳启动（iOS/Android 锁屏防休眠已就绪）');
      } else {
        await _keeperPlayer.resume();
      }
    } catch (e) {
      debugPrint('[KeepAlive] 启动静音守护异常: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('[Lifecycle] App 进入后台/锁屏状态，确保守护心跳运行');
      _updateKeeperState();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[Lifecycle] App 返回前台，立即校准连接与状态');
      refreshStatus();
    }
  }

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    _isVoiceReplyEnabled = prefs.getBool(_prefKeyVoiceReply) ?? false;

    // 配置全局 AudioContext，打通 iOS/Android 锁屏后台播放通道
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
    } catch (e) {
      debugPrint('[Audio] 配置全局音频上下文失败: $e');
    }

    _audioPlayer.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (_isPlayingAudio != playing) {
        _isPlayingAudio = playing;
        if (!playing && state != PlayerState.paused && _nextQueuedMusicUrl == null) {
          _currentPlayingUrl = null;
        }
        notifyListeners();
        if (!playing) {
          _updateKeeperState();
        }
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      _isPlayingAudio = false;
      if (_nextQueuedMusicUrl != null) {
        final nextSong = _nextQueuedMusicUrl!;
        _nextQueuedMusicUrl = null;
        playAudio(nextSong);
      } else {
        _currentPlayingUrl = null;
        notifyListeners();
        _updateKeeperState();
      }
    });

    final configStr = prefs.getString(_prefKeyConfig);
    if (configStr != null) {
      try {
        _config = ServerConfig.fromJson(jsonDecode(configStr) as Map<String, dynamic>);
        _apiClient.updateConfig(_config);
      } catch (_) {}
    }

    final historyStr = prefs.getString(_prefKeyMessages);
    if (historyStr != null) {
      try {
        final list = jsonDecode(historyStr) as List<dynamic>;
        _messages = list.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    final routineStr = prefs.getString(_prefKeyRoutine);
    if (routineStr != null) {
      try {
        _routineConfig = RoutineConfig.fromJson(jsonDecode(routineStr) as Map<String, dynamic>);
      } catch (_) {}
    }

    _isInitialized = true;
    notifyListeners();

    // 尝试拉取一次状态与启动长轮询
    await refreshStatus();
    _startPeriodicStatusCheck();
    _startEventPolling();
    _syncRoutineWithServer();
    _startLocalRoutineTimer();
    _updateKeeperState();
  }

  Future<void> _syncRoutineWithServer() async {
    try {
      final remote = await _apiClient.fetchRoutineConfig();
      if (remote != null) {
        _routineConfig = RoutineConfig.fromJson(remote);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyRoutine, jsonEncode(_routineConfig.toJson()));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveRoutineConfig(RoutineConfig newConfig) async {
    _routineConfig = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyRoutine, jsonEncode(newConfig.toJson()));
    notifyListeners();
    await _updateKeeperState();
    // 异步同步到小主机常驻守护
    await _apiClient.updateRoutineConfig(newConfig.toJson());
  }

  void _startLocalRoutineTimer() {
    _localRoutineTimer?.cancel();
    _localRoutineTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_isConnected) return;
      final now = DateTime.now();
      String pad(int n) => n.toString().padLeft(2, '0');
      final dateStr = '${now.year}-${pad(now.month)}-${pad(now.day)}';
      final timeStr = '${pad(now.hour)}:${pad(now.minute)}';

      // 本地早安双保险唤醒
      if (_routineConfig.morningCallEnabled &&
          timeStr == _routineConfig.morningCallTime &&
          _lastLocalMorningDate != dateStr) {
        _lastLocalMorningDate = dateStr;
        debugPrint('[Routine] 触发手机端本地晨光早安双保险唤醒');
        _isVoiceReplyEnabled = true;
        unawaited(sendMessage('夫君醒来啦，快来给相公请早安'));
      }

      // 本地晚安双保险催歇
      if (_routineConfig.nightSleepEnabled &&
          timeStr == _routineConfig.nightSleepTime &&
          _lastLocalNightDate != dateStr) {
        _lastLocalNightDate = dateStr;
        debugPrint('[Routine] 触发手机端本地深夜催歇双保险');
        _isVoiceReplyEnabled = true;
        unawaited(sendMessage('夜深啦，相公准备歇息了'));
      }
    });
  }

  Future<bool> saveConfig(ServerConfig newConfig) async {
    _config = newConfig;
    _apiClient.updateConfig(newConfig);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyConfig, jsonEncode(newConfig.toJson()));

    final ok = await refreshStatus();
    notifyListeners();
    return ok;
  }

  Future<bool> refreshStatus() async {
    final ok = await _apiClient.checkHealth();
    _isConnected = ok;
    if (ok) {
      _petStatus = await _apiClient.fetchStatus();
    } else {
      _petStatus = PetStatus(online: false);
    }
    notifyListeners();
    return ok;
  }

  void _startPeriodicStatusCheck() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshStatus();
    });
  }

  /// 启动主动事件长轮询（AI 主动搭话监听）
  void _startEventPolling() {
    if (_pollingActive) return;
    _pollingActive = true;
    _runPollingLoop();
  }

  Future<void> _runPollingLoop() async {
    while (_pollingActive) {
      if (!_isConnected || _config.token.isEmpty) {
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }

      try {
        final data = await _apiClient.pollEvents(since: _lastEventSeq, waitMs: 25000);
        if (data != null && data['ok'] == true) {
          final events = data['events'] as List<dynamic>? ?? [];
          final lastSeq = data['lastSeq'] as int?;
          if (lastSeq != null) {
            _lastEventSeq = lastSeq;
          }

          for (final ev in events) {
            final e = ev as Map<String, dynamic>;
            final type = e['type'] as String?;
            final text = e['text'] as String?;

            // 监听主动搭话与回复事件
            if ((type == 'proactive' || type == 'reply') && text != null && text.isNotEmpty) {
              final audioKey = e['audioKey'] as String?;
              String? audioUrl;
              if (audioKey != null && audioKey.isNotEmpty) {
                audioUrl = '${_config.apiPrefix}/audio/$audioKey.wav?token=${Uri.encodeComponent(_config.token.trim())}';
              }

              final proactiveMsg = ChatMessage(
                id: e['messageId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
                text: text,
                isUser: false,
                timestamp: DateTime.now(),
                modality: e['modality'] as String? ?? 'text',
                audioUrl: audioUrl,
              );

              // 避免重复追加
              if (!_messages.any((m) => m.id == proactiveMsg.id)) {
                _messages.add(proactiveMsg);
                _persistMessages();
                notifyListeners();

                final musicUrl = proactiveMsg.detectedMusicUrl;
                if (musicUrl != null && musicUrl.isNotEmpty) {
                  if (proactiveMsg.audioUrl != null && proactiveMsg.audioUrl!.isNotEmpty) {
                    _nextQueuedMusicUrl = musicUrl;
                    unawaited(playAudio(proactiveMsg.audioUrl!));
                  } else {
                    unawaited(playAudio(musicUrl));
                  }
                } else if (proactiveMsg.audioUrl != null && proactiveMsg.audioUrl!.isNotEmpty) {
                  // 主动关怀（早安唤醒/晚安催歇）自带语音，无条件播放叫醒主人！
                  unawaited(playAudio(proactiveMsg.audioUrl!));
                }
              }
            }
          }
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  /// 切换语音回复开关（右上角豆包同款开关，开启才调用火山TTS，关闭省额度）
  Future<void> toggleVoiceReply() async {
    _isVoiceReplyEnabled = !_isVoiceReplyEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyVoiceReply, _isVoiceReplyEnabled);
    if (!_isVoiceReplyEnabled) {
      await stopAudio();
    }
    notifyListeners();
  }

  /// 播放音频（支持气泡点击播放或自动播报）
  Future<void> playAudio(String url) async {
    try {
      if (_currentPlayingUrl == url && _isPlayingAudio) {
        await _audioPlayer.pause();
        _isPlayingAudio = false;
        notifyListeners();
        await _updateKeeperState();
        return;
      }
      _currentPlayingUrl = url;
      _isPlayingAudio = true;
      notifyListeners();
      try {
        await _keeperPlayer.pause();
      } catch (_) {}
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('[Audio] 播放音频失败: $e');
      _isPlayingAudio = false;
      _currentPlayingUrl = null;
      notifyListeners();
      await _updateKeeperState();
    }
  }

  /// 停止音频播放
  Future<void> stopAudio() async {
    _nextQueuedMusicUrl = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    _isPlayingAudio = false;
    _currentPlayingUrl = null;
    notifyListeners();
    await _updateKeeperState();
  }

  /// 测试锁屏叫醒（支持秒数倒计时后触发）
  Future<void> testLockScreenWakeup({int delaySeconds = 3}) async {
    await _updateKeeperState();
    debugPrint('[TestWakeup] 启动锁屏测试，将于 $delaySeconds 秒后在后台触发叫醒...');
    Timer(Duration(seconds: delaySeconds), () async {
      debugPrint('[TestWakeup] 触发测试叫醒！');
      final testMsg = ChatMessage(
        id: 'test_wake_${DateTime.now().millisecondsSinceEpoch}',
        text: '夫君！妾身成功在锁屏下叫醒你啦~ 妾身一直守在夫君身边呢！[emoji:hug]',
        isUser: false,
        timestamp: DateTime.now(),
        modality: 'voice',
      );
      _messages.add(testMsg);
      _persistMessages();
      notifyListeners();

      try {
        final res = await _apiClient.sendMessage('夫君醒来啦，快来给相公请早安', modality: 'voice');
        if (res.audioUrl != null && res.audioUrl!.isNotEmpty) {
          await playAudio(res.audioUrl!);
        }
      } catch (err) {
        debugPrint('[TestWakeup] 测试叫醒失败: $err');
      }
    });
  }

  /// 发送一条消息
  Future<void> sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _isSending) return;

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: clean,
      isUser: true,
      timestamp: DateTime.now(),
    );

    final pendingId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    final pendingMsg = ChatMessage(
      id: pendingId,
      text: '正在思考...',
      isUser: false,
      timestamp: DateTime.now(),
      isPending: true,
    );

    _messages.add(userMsg);
    _messages.add(pendingMsg);
    _isSending = true;
    notifyListeners();
    _persistMessages();

    try {
      // 核心控制：语音开关开启时才传 voice（触发火山TTS），关闭时传 text（完全不调用火山引擎，0耗额度）
      final modality = _isVoiceReplyEnabled ? 'voice' : 'text';
      final reply = await _apiClient.sendMessage(clean, modality: modality);
      final idx = _messages.indexWhere((m) => m.id == pendingId);
      if (idx != -1) {
        _messages[idx] = reply;
      } else {
        _messages.add(reply);
      }
      _isConnected = true;

      // 自动播放联动：小娘子唱曲与语音
      final musicUrl = reply.detectedMusicUrl;
      if (musicUrl != null && musicUrl.isNotEmpty) {
        if (_isVoiceReplyEnabled && reply.audioUrl != null && reply.audioUrl!.isNotEmpty) {
          // 语音模式下：先播放小娘子引言，引言结束后自动无缝起唱歌曲
          _nextQueuedMusicUrl = musicUrl;
          unawaited(playAudio(reply.audioUrl!));
        } else {
          // 纯文字模式下：直接自动起唱歌曲
          unawaited(playAudio(musicUrl));
        }
      } else if (_isVoiceReplyEnabled && reply.audioUrl != null && reply.audioUrl!.isNotEmpty) {
        // 普通语音回复自动播报
        unawaited(playAudio(reply.audioUrl!));
      }
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == pendingId);
      if (idx != -1) {
        _messages[idx] = ChatMessage(
          id: pendingId,
          text: '消息发送失败: $e',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        );
      }
    } finally {
      _isSending = false;
      _persistMessages();
      notifyListeners();
    }
  }

  /// 清空本地聊天历史记录
  Future<void> clearHistory() async {
    _messages.clear();
    await stopAudio();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyMessages);
    notifyListeners();
  }

  void _persistMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _messages.map((m) => m.toJson()).toList();
      await prefs.setString(_prefKeyMessages, jsonEncode(jsonList));
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localRoutineTimer?.cancel();
    _pollingActive = false;
    _statusTimer?.cancel();
    _audioPlayer.dispose();
    _keeperPlayer.dispose();
    super.dispose();
  }
}
