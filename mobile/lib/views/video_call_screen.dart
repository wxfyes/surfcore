import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  bool _isInspecting = false; // 是否正在让娘子端详我

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
      }
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
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isSpeaking = provider.isPlayingAudio;

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
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isSpeaking ? '正在对相公呢喃软语……' : '深情倾听相公中……',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
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

          // 4. 下方字幕与视觉感知浮窗
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
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    _subtitleText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
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

                // 让娘子端详我（拍照并由 Gemini 3.5 Flash 视觉识别）
                _buildCircleButton(
                  icon: _isInspecting ? Icons.hourglass_top_rounded : Icons.remove_red_eye_rounded,
                  label: _isInspecting ? '端详中...' : '看相公',
                  highlight: true,
                  onTap: _isInspecting ? null : _inspectMe,
                ),

                // 麦克风开关
                _buildCircleButton(
                  icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: _isMuted ? '已静音' : '麦克风',
                  onTap: () {
                    setState(() => _isMuted = !_isMuted);
                  },
                ),

                // 红色挂断大按钮
                GestureDetector(
                  onTap: () {
                    provider.stopAudio();
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
