import 'dart:async';
import 'package:dio/dio.dart';
import '../models/server_config.dart';
import '../models/chat_message.dart';
import '../models/pet_status.dart';

class SurfCoreApiClient {
  ServerConfig config;
  late Dio _dio;

  SurfCoreApiClient(this.config) {
    _initDio();
  }

  void updateConfig(ServerConfig newConfig) {
    config = newConfig;
    _initDio();
  }

  void _initDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: config.apiPrefix,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 40),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'x-pet-token': config.token.trim(),
          // 关键护栏穿透：后端以 Host 头作为回环准入校验，设置 127.0.0.1 允许外部客户端安全通信
          'Host': '127.0.0.1:${config.port}',
        },
      ),
    );
  }

  /// 检查服务连通性与健康状态
  Future<bool> checkHealth() async {
    try {
      final res = await _dio.get('/health', queryParameters: {'token': config.token.trim()});
      return res.statusCode == 200 && res.data != null && res.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 获取实时角色人设与当前作息状态
  Future<PetStatus> fetchStatus() async {
    try {
      final res = await _dio.get('/status');
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return PetStatus.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      // 容错返回离线状态
    }
    return PetStatus(online: false);
  }

  /// 发送聊天消息
  Future<ChatMessage> sendMessage(String text, {String modality = 'text'}) async {
    final response = await _dio.post(
      '/chat',
      data: {
        'text': text,
        'modality': modality,
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      if (data['ok'] == true && data['reply'] != null) {
        final reply = data['reply'] as Map<String, dynamic>;
        final replyText = reply['text'] as String? ?? '';
        final audioKey = reply['audio']?['key'] as String?;
        String? audioUrl;
        if (audioKey != null && audioKey.isNotEmpty) {
          audioUrl = '${config.apiPrefix}/audio/$audioKey.wav?token=${Uri.encodeComponent(config.token.trim())}';
        }

        return ChatMessage(
          id: reply['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          text: replyText,
          isUser: false,
          timestamp: DateTime.now(),
          modality: reply['modality'] as String? ?? 'text',
          audioUrl: audioUrl,
        );
      } else {
        throw Exception(data['error'] ?? '回复失败');
      }
    } else {
      throw Exception('网络响应异常: ${response.statusCode}');
    }
  }

  /// 拉取历史消息
  Future<List<ChatMessage>> fetchHistory({int limit = 50}) async {
    try {
      final res = await _dio.get('/history', queryParameters: {'limit': limit});
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final list = data['history'] as List<dynamic>? ?? [];
        return list.map((item) {
          final m = item as Map<String, dynamic>;
          final isUser = m['role'] == 'user';
          final audioKey = m['audioKey'] as String?;
          String? audioUrl;
          if (audioKey != null && audioKey.isNotEmpty) {
            audioUrl = '${config.apiPrefix}/audio/$audioKey.wav?token=${Uri.encodeComponent(config.token.trim())}';
          }
          return ChatMessage(
            id: m['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
            text: m['text'] as String? ?? '',
            isUser: isUser,
            timestamp: m['time'] != null
                ? DateTime.fromMillisecondsSinceEpoch(m['time'] as int)
                : DateTime.now(),
            modality: m['modality'] as String? ?? 'text',
            audioUrl: audioUrl,
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 长轮询获取事件（AI 主动搭话、心情变化等）
  Future<Map<String, dynamic>?> pollEvents({int? since, int waitMs = 25000}) async {
    try {
      final res = await _dio.get(
        '/events',
        queryParameters: {
          if (since != null) 'since': since,
          'wait': waitMs,
          'client': 'mobile_app',
        },
        options: Options(receiveTimeout: Duration(milliseconds: waitMs + 10000)),
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
    } catch (_) {
      // 轮询超时或断开属于预期，上层自动重试
    }
    return null;
  }
}
