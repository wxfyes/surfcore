import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';
import '../models/chat_message.dart';
import '../models/pet_status.dart';
import '../models/routine_config.dart';
import '../services/api_client.dart';

class ChatProvider extends ChangeNotifier {
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

  // 豆包风格语音播放开关与播放器
  bool _isVoiceReplyEnabled = false; // 默认关闭，让用户右上角自由开启（省火山额度）
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentPlayingUrl;
  String? _nextQueuedMusicUrl;
  bool _isPlayingAudio = false;

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

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _isVoiceReplyEnabled = prefs.getBool(_prefKeyVoiceReply) ?? false;

    _audioPlayer.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (_isPlayingAudio != playing) {
        _isPlayingAudio = playing;
        if (!playing && state != PlayerState.paused && _nextQueuedMusicUrl == null) {
          _currentPlayingUrl = null;
        }
        notifyListeners();
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
        unawaited(sendMessage('相公醒来啦，快来给相公请早安'));
      }

      // 本地晚安双保险催歇
      if (_routineConfig.nightSleepEnabled &&
          timeStr == _routineConfig.nightSleepTime &&
          _lastLocalNightDate != dateStr) {
        _lastLocalNightDate = dateStr;
        debugPrint('[Routine] 触发手机端本地深夜催歇双保险');
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
                  if (_isVoiceReplyEnabled && proactiveMsg.audioUrl != null && proactiveMsg.audioUrl!.isNotEmpty) {
                    _nextQueuedMusicUrl = musicUrl;
                    unawaited(playAudio(proactiveMsg.audioUrl!));
                  } else {
                    unawaited(playAudio(musicUrl));
                  }
                } else if (_isVoiceReplyEnabled && proactiveMsg.audioUrl != null && proactiveMsg.audioUrl!.isNotEmpty) {
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
        return;
      }
      _currentPlayingUrl = url;
      _isPlayingAudio = true;
      notifyListeners();
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('[Audio] 播放音频失败: $e');
      _isPlayingAudio = false;
      _currentPlayingUrl = null;
      notifyListeners();
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
    _pollingActive = false;
    _statusTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
