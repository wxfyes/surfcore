class ServerConfig {
  final String host; // 例如 "192.168.1.213" 或 Tailscale IP
  final int port; // 默认 3080
  final String token; // pet-token
  final bool useHttps;

  const ServerConfig({
    required this.host,
    this.port = 3080,
    required this.token,
    this.useHttps = false,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    final cleanHost = host.trim().replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    return '$scheme://$cleanHost:$port';
  }

  String get apiPrefix => '$baseUrl/dsh-surfcore/pet-api';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'token': token,
        'useHttps': useHttps,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        host: json['host'] as String? ?? '127.0.0.1',
        port: json['port'] as int? ?? 3080,
        token: json['token'] as String? ?? '',
        useHttps: json['useHttps'] as bool? ?? false,
      );

  ServerConfig copyWith({
    String? host,
    int? port,
    String? token,
    bool? useHttps,
  }) {
    return ServerConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      useHttps: useHttps ?? this.useHttps,
    );
  }
}
