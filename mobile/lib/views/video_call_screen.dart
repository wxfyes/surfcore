import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  bool _isInspecting = false;

  // 语音识别 STT
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String _currentLocaleId = 'zh_CN';
  bool _isListening = false;
  bool _isSending = false;
  String _liveSpokenWords = '';
  Timer? _silenceTimer;
  bool _wasPlayingAudio = false;
  bool _isHoldingToTalk = false;

  // 防抖单次原子锁
  DateTime _lastSendTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSentWords = '';

  // 通话时长
  int _callDurationSeconds = 0;
  Timer? _durationTimer;

  // 动效控制器：3D豆包卡通形象呼吸、眨眼与声浪脉冲
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  Timer? _blinkRandomTimer;

  String _subtitleText = '相公，视频已接通啦……让妾身好好瞧瞧你~';
  String _visualFactNotice = '';

  @override
  void initState() {
    super.initState();
    _startDurationTimer();
    _initAnimations();
    _initCamera();
    _initSpeech();

    // 接通 1.2 秒后小娘子主动问候
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _triggerVideoGreeting();
      }
    });
  }

  void _initAnimations() {
    // 1. 身体起伏呼吸律动
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _breatheAnimation = Tween<double>(begin: 0.98, end: 1.04).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // 2. 灵动眨眼动画
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.05).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _blinkRandomTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && math.Random().nextBool()) {
        _blinkController.forward().then((_) {
          if (mounted) _blinkController.reverse();
        });
      }
    });
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

      int frontIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _selectedCameraIndex = frontIndex != -1 ? frontIndex : 0;
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
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (status) {
          debugPrint('[VideoCall STT] 状态变更: $status');
          if (status == 'notListening' || status == 'done') {
            if (mounted && !_isSending && _liveSpokenWords.trim().isNotEmpty) {
              _sendSpokenMessage(_liveSpokenWords.trim());
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
        } catch (_) {
          _currentLocaleId = 'zh_CN';
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      _speechAvailable = false;
    }
  }

  /// 倾听相公说话
  Future<void> _startListeningToHusband() async {
    if (!_speechAvailable || _isMuted || _isSending) return;
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    if (provider.isPlayingAudio) return;

    if (_speech.isListening) return;

    try {
      setState(() {
        _isListening = true;
        _liveSpokenWords = '';
      });

      await _speech.listen(
        onResult: (result) {
          if (!mounted || _isSending) return;
          final words = result.recognizedWords.trim();
          setState(() {
            _liveSpokenWords = words;
          });

          _silenceTimer?.cancel();
          if (words.isNotEmpty && !_isSending) {
            if (result.finalResult) {
              _sendSpokenMessage(words);
            } else {
              _silenceTimer = Timer(const Duration(milliseconds: 1600), () {
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

  /// 发送相公的话（智能区分：日常说话零拍照免快门；只有需要端详时才静默拍照）
  Future<void> _sendSpokenMessage(String text, {bool forceInspect = false}) async {
    final clean = text.trim();
    if (clean.isEmpty || _isSending) return;

    // 严格原子防抖锁定：绝不并发重复发起请求打断！
    final now = DateTime.now();
    if (clean == _lastSentWords && now.difference(_lastSendTimestamp).inSeconds < 3) {
      return;
    }

    _lastSentWords = clean;
    _lastSendTimestamp = now;

    _silenceTimer?.cancel();
    final provider = context.read<ChatProvider>();
    await _stopListening();

    // 智能识别视觉意图：只有相公说“看我/穿搭/气色”或手动点击看相公，才拍照！
    final isVisionIntent = forceInspect ||
        RegExp(r'看我|看穿搭|瞧瞧我|看相公|好看吗|穿得怎么样|气色|自拍|端详|瞧我|我帅不帅|我好看吗').hasMatch(clean);

    setState(() {
      _isSending = true;
      _liveSpokenWords = '';
      if (isVisionIntent) {
        _subtitleText = '相公：“$clean”\n（妾身正端详相公气色……）';
      } else {
        _subtitleText = '相公：“$clean”\n（妾身正细细琢磨……）';
      }
    });

    String? imageBase64;
    if (isVisionIntent) {
      imageBase64 = await _captureFrameBase64();
    }

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

  /// 翻转前后摄像头
  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _setupCameraController(_cameras[_selectedCameraIndex]);
  }

  /// 接通首帧问候
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

  /// 捕获摄像头一帧
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

  /// 手动点击“看相公”端详按钮
  Future<void> _inspectMe() async {
    if (_isInspecting || _isSending) return;
    setState(() => _isInspecting = true);
    await _sendSpokenMessage('相公正在镜头前，请端详他的穿搭神色，娇嗔点评一番。', forceInspect: true);
    if (mounted) setState(() => _isInspecting = false);
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _getStatusText(bool isSpeaking) {
    if (isSpeaking) return '正在对相公呢喃软语……';
    if (_isSending) return '娘子正在凝眸思量……';
    if (_isHoldingToTalk) return '正在聆听相公圣谕，松手送达……';
    if (_liveSpokenWords.isNotEmpty) return '正在倾听相公说话……';
    if (_isListening) return '深情倾听相公中……';
    if (_isMuted) return '麦克风已静音';
    return '视讯连接就绪';
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
    _blinkRandomTimer?.cancel();
    _speech.stop();
    _breatheController.dispose();
    _blinkController.dispose();
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
      backgroundColor: const Color(0xFF0F0C1B),
      body: Stack(
        children: [
          // 1. 全屏沉浸梦幻背景：深邃渐变与微星光
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 1.25,
                  colors: [
                    Color(0xFF2A1647),
                    Color(0xFF150D27),
                    Color(0xFF0A0713),
                  ],
                ),
              ),
            ),
          ),

          // 2. 核心主角：豆包同款 3D 萌系立体可爱小娘子动画形象（眨眼、呼吸律动、声浪光波）
          Positioned.fill(
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_breatheAnimation, _blinkAnimation]),
                builder: (context, child) {
                  return Transform.scale(
                    scale: isSpeaking ? (_breatheAnimation.value * 1.05) : _breatheAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 3D 豆包立体虚拟人
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // 说话时的梦幻立体声浪光晕
                            if (isSpeaking) ...[
                              Container(
                                width: 250,
                                height: 250,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD946EF).withValues(alpha: 0.35),
                                      blurRadius: 50,
                                      spreadRadius: 16,
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                      blurRadius: 80,
                                      spreadRadius: 30,
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // 3D 粘土软萌卡通小娘子身体与面部
                            CustomPaint(
                              size: const Size(220, 220),
                              painter: Doubao3DAvatarPainter(
                                isSpeaking: isSpeaking,
                                eyeOpenFactor: _blinkAnimation.value,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        // 娘子姓名与状态
                        Text(
                          provider.petStatus.characterName.isNotEmpty
                              ? provider.petStatus.characterName
                              : '傲娇小娘子',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                            shadows: [
                              Shadow(color: Color(0x88D946EF), blurRadius: 12),
                            ],
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
                                boxShadow: [
                                  BoxShadow(
                                    color: _getStatusColor(isSpeaking).withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getStatusText(isSpeaking),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // 3. 右上角画中画：用户前置摄像头画面（相公实时视角）
          Positioned(
            top: 54,
            right: 18,
            child: Container(
              width: 110,
              height: 155,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
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

          // 4. 顶部通话时长与返回键
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

          // 5. 下方字幕与实时语音识别浮窗
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
                      color: const Color(0xFF6D28D9).withValues(alpha: 0.4),
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
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.15),
                      width: _liveSpokenWords.isNotEmpty ? 1.5 : 1,
                    ),
                    boxShadow: _liveSpokenWords.isNotEmpty
                        ? [
                            BoxShadow(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
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

          // 6. 底部视讯控制栏
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

                // 让娘子端详我（只有点击此按钮或说“看我”才拍照，日常说话不拍照）
                _buildCircleButton(
                  icon: _isInspecting ? Icons.hourglass_top_rounded : Icons.remove_red_eye_rounded,
                  label: _isInspecting ? '端详中...' : '看相公',
                  highlight: true,
                  onTap: _isInspecting ? null : _inspectMe,
                ),

                // 麦克风（支持点击静音/开麦，也支持长按对讲）
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

                // 挂断按钮
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

/// 豆包风格 3D 萌系立体可爱小娘子动画形象绘制器
class Doubao3DAvatarPainter extends CustomPainter {
  final bool isSpeaking;
  final double eyeOpenFactor; // 1.0 为睁眼，0.0 为闭眼/眨眼

  Doubao3DAvatarPainter({
    required this.isSpeaking,
    required this.eyeOpenFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.2;

    // 1. 3D 立体柔糯面庞底色（豆包同款柔光渐变球体）
    final headPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 0.9,
        colors: const [
          Color(0xFFFFF0F5), // 柔白高光
          Color(0xFFFFD8E4), // 娇嫩粉白
          Color(0xFFF9A8D4), // 边缘立体暗调
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, headPaint);

    // 2. 豆包同款软萌发髻与小发簪
    final bunCenter = Offset(center.dx, center.dy - radius * 0.85);
    final bunPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4C1D95), Color(0xFF2E1065)],
      ).createShader(Rect.fromCircle(center: bunCenter, radius: radius * 0.45));
    canvas.drawCircle(bunCenter, radius * 0.38, bunPaint);

    // 发簪珠玉（金翠微光）
    final pinPaint = Paint()..color = const Color(0xFFFDE047);
    canvas.drawCircle(Offset(bunCenter.dx + radius * 0.35, bunCenter.dy), 7, pinPaint);
    final pearlPaint = Paint()..color = const Color(0xFF34D399);
    canvas.drawCircle(Offset(bunCenter.dx + radius * 0.48, bunCenter.dy + 8), 5, pearlPaint);

    // 3. 娇羞粉嫩小腮红
    final blushPaint = Paint()
      ..color = const Color(0xFFFB7185).withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx - radius * 0.52, center.dy + radius * 0.15), width: 34, height: 20),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx + radius * 0.52, center.dy + radius * 0.15), width: 34, height: 20),
      blushPaint,
    );

    // 4. 灵动水灵灵大眼睛（支持眨眼与弯月笑眼）
    final eyeY = center.dy - radius * 0.05;
    final leftEyeX = center.dx - radius * 0.36;
    final rightEyeX = center.dx + radius * 0.36;

    if (isSpeaking) {
      // 说话时甜美弯月笑眼
      final smileEyePaint = Paint()
        ..color = const Color(0xFF2E1065)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      final leftPath = Path()
        ..moveTo(leftEyeX - 16, eyeY + 2)
        ..quadraticBezierTo(leftEyeX, eyeY - 12, leftEyeX + 16, eyeY + 2);
      canvas.drawPath(leftPath, smileEyePaint);

      final rightPath = Path()
        ..moveTo(rightEyeX - 16, eyeY + 2)
        ..quadraticBezierTo(rightEyeX, eyeY - 12, rightEyeX + 16, eyeY + 2);
      canvas.drawPath(rightPath, smileEyePaint);
    } else {
      // 平时水灵灵大眼睛（眨眼缩放）
      final eyeHeight = 26.0 * eyeOpenFactor;
      final eyePaint = Paint()..color = const Color(0xFF1E1035);

      if (eyeHeight > 2.0) {
        // 眼眶底色
        canvas.drawOval(
          Rect.fromCenter(center: Offset(leftEyeX, eyeY), width: 22, height: eyeHeight),
          eyePaint,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(rightEyeX, eyeY), width: 22, height: eyeHeight),
          eyePaint,
        );

        // 纯真水润高光点
        if (eyeOpenFactor > 0.6) {
          final glintPaint = Paint()..color = Colors.white;
          canvas.drawCircle(Offset(leftEyeX - 3, eyeY - 5), 4.5, glintPaint);
          canvas.drawCircle(Offset(leftEyeX + 3, eyeY + 4), 2.5, glintPaint);
          canvas.drawCircle(Offset(rightEyeX - 3, eyeY - 5), 4.5, glintPaint);
          canvas.drawCircle(Offset(rightEyeX + 3, eyeY + 4), 2.5, glintPaint);
        }
      } else {
        // 闭眼一条细缝
        final closePaint = Paint()
          ..color = const Color(0xFF2E1065)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5;
        canvas.drawLine(Offset(leftEyeX - 12, eyeY), Offset(leftEyeX + 12, eyeY), closePaint);
        canvas.drawLine(Offset(rightEyeX - 12, eyeY), Offset(rightEyeX + 12, eyeY), closePaint);
      }
    }

    // 5. 灵动小嘴巴（说话时微张动效，闭嘴时甜甜微笑）
    final mouthPaint = Paint()
      ..color = const Color(0xFFE11D48)
      ..style = isSpeaking ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final mouthY = center.dy + radius * 0.42;
    if (isSpeaking) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(center.dx, mouthY), width: 18, height: 14),
        mouthPaint,
      );
    } else {
      final mouthPath = Path()
        ..moveTo(center.dx - 12, mouthY - 2)
        ..quadraticBezierTo(center.dx, mouthY + 8, center.dx + 12, mouthY - 2);
      canvas.drawPath(mouthPath, mouthPaint);
    }
  }

  @override
  bool shouldRepaint(covariant Doubao3DAvatarPainter oldDelegate) {
    return oldDelegate.isSpeaking != isSpeaking || oldDelegate.eyeOpenFactor != eyeOpenFactor;
  }
}
