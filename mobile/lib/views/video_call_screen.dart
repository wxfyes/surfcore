import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../providers/chat_provider.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> with TickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;
  bool _isCameraReady = false;
  bool _isMuted = false;
  bool _isInspecting = false; // 是否正在主动点击“看相公”

  // 语音识别 STT
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String _currentLocaleId = 'zh_CN';
  bool _isListening = false;
  bool _isSending = false;
  String _liveSpokenWords = '';
  Timer? _silenceTimer;
  bool _wasPlayingAudio = false;
  bool _isHoldingToTalk = false; // 是否手动按住说话

  // 通话时长
  int _callDurationSeconds = 0;
  Timer? _durationTimer;

  // 动效控制器（小娘子说话声浪波纹与心跳）
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _subtitleText = '相公，视频已接通啦……让妾身好好瞧瞧你~';
  String _visualFactNotice = '';

  @override
  void initState() {
    super.initState();
    _startDurationTimer();
    _initAnimation();
    _initCamera();
    _initSpeech();

    // 视讯接通后 1.2 秒，小娘子主动向相公问安
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _triggerVideoGreeting();
      }
    });
  }

  void _initAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // 默认优先选择前置摄像头看相公
      int frontIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (frontIndex != -1) {
        _selectedCameraIndex = frontIndex;
      } else {
        _selectedCameraIndex = 0;
      }

      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('[VideoCall] 初始化摄像头异常: $e');
    }
  }

  Future<void> _setupCameraController(CameraDescription description) async {
    await _cameraController?.dispose();
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _cameraController = controller;
          _isCameraReady = true;
        });
      }
    } catch (e) {
      debugPrint('[VideoCall] 启动摄像头控制器失败: $e');
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          debugPrint('[VideoCall STT] 识别错误: $val');
          if (mounted) {
            setState(() => _isListening = false);
          }
        },
        onStatus: (status) {
          debugPrint('[VideoCall STT] 状态变更: $status');
          if (status == 'notListening' || status == 'done') {
            if (mounted && _isListening && !_isSending) {
              _checkAndAutoSend();
            }
          }
        },
      );

      if (_speechAvailable) {
        try {
          final systemLocale = await _speech.systemLocale();
          final locales = await _speech.locales();
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
          debugPrint('[VideoCall STT] 语音引擎就绪，选定模型: $_currentLocaleId');
        } catch (e) {
          _currentLocaleId = 'zh_CN';
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[VideoCall STT] 初始化失败: $e');
      _speechAvailable = false;
    }
  }

  /// 倾听相公说话
  Future<void> _startListeningToHusband() async {
    if (!_speechAvailable || _isMuted || _isSending) return;
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    if (provider.isPlayingAudio) return;

    if (_speech.isListening) {
      return;
    }

    try {
      setState(() {
        _isListening = true;
        _liveSpokenWords = '';
      });

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords.trim();
          setState(() {
            _liveSpokenWords = words;
          });

          // 相公停止说话后 1.5 秒无新字，自动抓拍画面与文字发送给娘子
          _silenceTimer?.cancel();
          if (words.isNotEmpty) {
            if (result.finalResult) {
              _sendSpokenMessage(words);
            } else {
              _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
                if (mounted && _liveSpokenWords.isNotEmpty && !_isSending) {
                  _sendSpokenMessage(_liveSpokenWords);
                }
              });
            }
          }
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
      debugPrint('[VideoCall STT] 启动监听异常: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _checkAndAutoSend() {
    if (_liveSpokenWords.trim().isNotEmpty && !_isSending) {
      _sendSpokenMessage(_liveSpokenWords.trim());
    } else {
      if (mounted) setState(() => _isListening = false);
      // 若没有说话，稍作延迟后再次恢复待命监听
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_isMuted && !_isSending) {
          _startListeningToHusband();
        }
      });
    }
  }

  Future<void> _stopListening() async {
    _silenceTimer?.cancel();
    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  /// 翻转前后摄像头
  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _setupCameraController(_cameras[_selectedCameraIndex]);
  }

  /// 通话刚接通时的主动问候
  Future<void> _triggerVideoGreeting() async {
    final provider = context.read<ChatProvider>();
    String? imageBase64 = await _captureFrameBase64();

    final res = await provider.sendVideoCallFrame(
      text: '',
      imageBase64: imageBase64,
    );

    if (mounted && res['ok'] == true) {
      setState(() {
        _subtitleText = res['text'] as String? ?? '';
        if (res['visualFact'] != null && (res['visualFact'] as String).isNotEmpty) {
          _visualFactNotice = res['visualFact'] as String;
        }
      });
      final audioUrl = res['audioUrl'] as String?;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        unawaited(provider.playAudio(audioUrl));
      } else {
        _startListeningToHusband();
      }
    } else if (mounted) {
      _startListeningToHusband();
    }
  }

  /// 捕获当前摄像头一帧画面的 Base64
  Future<String?> _captureFrameBase64() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }
    try {
      final file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('[VideoCall] 抽帧异常: $e');
      return null;
    }
  }

  /// 发送相公的话及最新视频截帧
  Future<void> _sendSpokenMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _isSending) return;

    _silenceTimer?.cancel();
    final provider = context.read<ChatProvider>();
    await _stopListening();

    setState(() {
      _isSending = true;
      _subtitleText = '相公：“$clean”\n（妾身正在看着相公思量……）';
    });

    String? imageBase64 = await _captureFrameBase64();

    final res = await provider.sendVideoCallFrame(
      text: clean,
      imageBase64: imageBase64,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _liveSpokenWords = '';
        if (res['ok'] == true) {
          _subtitleText = res['text'] as String? ?? '';
          if (res['visualFact'] != null && (res['visualFact'] as String).isNotEmpty) {
            _visualFactNotice = res['visualFact'] as String;
          }
        } else {
          _subtitleText = '相公，网络稍有些卡顿，不过妾身满心都是相公~';
        }
      });

      final audioUrl = res['audioUrl'] as String?;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        unawaited(provider.playAudio(audioUrl));
      } else {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && !_isMuted) {
            _startListeningToHusband();
          }
        });
      }
    }
  }

  /// 点击“让娘子端详我”
  Future<void> _inspectMe() async {
    if (_isInspecting) return;
    setState(() {
      _isInspecting = true;
      _subtitleText = '妾身正在凝眸细细端详相公……';
    });

    final provider = context.read<ChatProvider>();
    String? imageBase64 = await _captureFrameBase64();

    final res = await provider.sendVideoCallFrame(
      text: '相公正在镜头前，请端详他的穿搭神色，娇嗔点评一番。',
      imageBase64: imageBase64,
    );

    if (mounted) {
      setState(() {
        _isInspecting = false;
        if (res['ok'] == true) {
          _subtitleText = res['text'] as String? ?? '';
          if (res['visualFact'] != null && (res['visualFact'] as String).isNotEmpty) {
            _visualFactNotice = res['visualFact'] as String;
          }
        } else {
          _subtitleText = '相公，网络稍有些卡顿，不过妾身满心都是相公~';
        }
      });

      final audioUrl = res['audioUrl'] as String?;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        unawaited(provider.playAudio(audioUrl));
      } else {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && !_isMuted) {
            _startListeningToHusband();
          }
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _getStatusText(bool isSpeaking) {
    if (isSpeaking) return '正在对相公呢喃软语……';
    if (_isSending) return '娘子正在凝眸端详相公……';
    if (_isHoldingToTalk) return '正在聆听相公圣谕，松手送达……';
    if (_liveSpokenWords.isNotEmpty) return '正在聆听相公说话……';
    if (_isListening) return '深情倾听相公中……';
    if (_isMuted) return '麦克风已静音';
    return '视讯连接已就绪';
  }

  Color _getStatusColor(bool isSpeaking) {
    if (isSpeaking) return const Color(0xFFD946EF);
    if (_isSending) return const Color(0xFFF59E0B);
    if (_isHoldingToTalk || _liveSpokenWords.isNotEmpty) return const Color(0xFF38BDF8);
    if (_isListening) return const Color(0xFF10B981);
    return Colors.white54;
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _silenceTimer?.cancel();
    _speech.stop();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isSpeaking = provider.isPlayingAudio;

    // 当小娘子说完话时，自动唤醒麦克风继续倾听相公
    if (_wasPlayingAudio && !isSpeaking) {
      _wasPlayingAudio = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isMuted && !_isSending && !_isListening) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && !_isMuted && !_isSending) {
              _startListeningToHusband();
            }
          });
        }
      });
    } else if (isSpeaking) {
      _wasPlayingAudio = true;
      if (_isListening) {
        _stopListening();
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF13111C),
      body: Stack(
        children: [
          // 1. 全屏背景沉浸：古典闺房暗调与小娘子温存立绘
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.2,
                  colors: [
                    Color(0xFF2E1A47),
                    Color(0xFF161026),
                    Color(0xFF0C0914),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 小娘子声浪脉冲立绘
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: isSpeaking ? _pulseAnimation.value : 1.0,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 呼吸光晕
                              if (isSpeaking)
                                Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                                        blurRadius: 40,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              // 唯美形象
                              Container(
                                width: 170,
                                height: 170,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSpeaking ? const Color(0xFFF472B6) : const Color(0xFF8B5CF6),
                                    width: 3,
                                  ),
                                  image: const DecorationImage(
                                    image: AssetImage('assets/images/pet_avatar.png'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      provider.petStatus.characterName.isNotEmpty
                          ? provider.petStatus.characterName
                          : '傲娇小娘子',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _getStatusColor(isSpeaking),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _getStatusText(isSpeaking),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. 右上角画中画：用户前置摄像头画面（相公实时视角）
          Positioned(
            top: 54,
            right: 18,
            child: Container(
              width: 110,
              height: 155,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_isCameraReady && _cameraController != null)
                    CameraPreview(_cameraController!)
                  else
                    const Center(
                      child: Icon(Icons.videocam_off, color: Colors.white54, size: 32),
                    ),
                  Positioned(
                    bottom: 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '相公视角',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. 顶部通话时长与状态
          Positioned(
            top: 54,
            left: 20,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '闺房视讯对聊',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _formatDuration(_callDurationSeconds),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 4. 下方字幕与实时语音识别浮窗
          Positioned(
            bottom: 125,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_visualFactNotice.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6D28D9).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '👀 娘子眼中的相公：$_visualFactNotice',
                      style: const TextStyle(color: Color(0xFFE9D5FF), fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _liveSpokenWords.isNotEmpty
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.15),
                      width: _liveSpokenWords.isNotEmpty ? 1.5 : 1,
                    ),
                    boxShadow: _liveSpokenWords.isNotEmpty
                        ? [
                            BoxShadow(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    _liveSpokenWords.isNotEmpty
                        ? '🗣️ 相公：“$_liveSpokenWords”'
                        : _subtitleText,
                    style: TextStyle(
                      color: _liveSpokenWords.isNotEmpty ? const Color(0xFFBAE6FD) : Colors.white,
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: _liveSpokenWords.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // 5. 底部豪华视讯控制栏
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 翻转前后摄像头
                _buildCircleButton(
                  icon: Icons.flip_camera_ios_rounded,
                  label: '翻转',
                  onTap: _toggleCamera,
                ),

                // 让娘子端详我（拍照并由视觉识别）
                _buildCircleButton(
                  icon: _isInspecting ? Icons.hourglass_top_rounded : Icons.remove_red_eye_rounded,
                  label: _isInspecting ? '端详中...' : '看相公',
                  highlight: true,
                  onTap: _isInspecting ? null : _inspectMe,
                ),

                // 麦克风（支持点击静音/开麦，也支持长按直接对讲）
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isMuted = !_isMuted;
                    });
                    if (_isMuted) {
                      _stopListening();
                    } else {
                      _startListeningToHusband();
                    }
                  },
                  onLongPressStart: (_) {
                    if (_isSending) return;
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _isHoldingToTalk = true;
                      _isMuted = false;
                    });
                    _startListeningToHusband();
                  },
                  onLongPressEnd: (_) {
                    if (!_isHoldingToTalk) return;
                    HapticFeedback.lightImpact();
                    setState(() => _isHoldingToTalk = false);
                    if (_liveSpokenWords.trim().isNotEmpty) {
                      _sendSpokenMessage(_liveSpokenWords.trim());
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _isMuted
                              ? Colors.white.withValues(alpha: 0.1)
                              : (_isHoldingToTalk || _liveSpokenWords.isNotEmpty
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF10B981).withValues(alpha: 0.8)),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isMuted
                                ? Colors.white24
                                : (_isHoldingToTalk || _liveSpokenWords.isNotEmpty
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF34D399)),
                            width: 1.5,
                          ),
                          boxShadow: [
                            if (!_isMuted)
                              BoxShadow(
                                color: (_isHoldingToTalk
                                        ? const Color(0xFF0284C7)
                                        : const Color(0xFF10B981))
                                    .withValues(alpha: 0.35),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: Icon(
                          _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isMuted ? '已静音' : (_isHoldingToTalk ? '松手发送' : '开麦中'),
                        style: TextStyle(
                          color: _isMuted ? Colors.white54 : const Color(0xFF6EE7B7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // 红色挂断大按钮
                GestureDetector(
                  onTap: () {
                    provider.stopAudio();
                    _speech.stop();
                    Navigator.pop(context);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x66EF4444),
                              blurRadius: 14,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 6),
                      const Text('挂断', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool highlight = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: highlight
                  ? const Color(0xFF8B5CF6)
                  : Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: highlight
                    ? const Color(0xFFC4B5FD)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
