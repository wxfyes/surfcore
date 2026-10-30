class RoutineConfig {
  final bool morningCallEnabled;
  final String morningCallTime; // "08:00"
  final bool nightSleepEnabled;
  final String nightSleepTime; // "23:30"
  final bool idleChatEnabled;
  final int idleChatIntervalHours; // 3
  final bool voiceEnabled;
  final bool keepAliveEnabled; // 锁屏夜间守护与晨光唤醒保活

  const RoutineConfig({
    this.morningCallEnabled = true,
    this.morningCallTime = '08:00',
    this.nightSleepEnabled = true,
    this.nightSleepTime = '23:30',
    this.idleChatEnabled = true,
    this.idleChatIntervalHours = 3,
    this.voiceEnabled = true,
    this.keepAliveEnabled = true,
  });

  RoutineConfig copyWith({
    bool? morningCallEnabled,
    String? morningCallTime,
    bool? nightSleepEnabled,
    String? nightSleepTime,
    bool? idleChatEnabled,
    int? idleChatIntervalHours,
    bool? voiceEnabled,
    bool? keepAliveEnabled,
  }) {
    return RoutineConfig(
      morningCallEnabled: morningCallEnabled ?? this.morningCallEnabled,
      morningCallTime: morningCallTime ?? this.morningCallTime,
      nightSleepEnabled: nightSleepEnabled ?? this.nightSleepEnabled,
      nightSleepTime: nightSleepTime ?? this.nightSleepTime,
      idleChatEnabled: idleChatEnabled ?? this.idleChatEnabled,
      idleChatIntervalHours: idleChatIntervalHours ?? this.idleChatIntervalHours,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      keepAliveEnabled: keepAliveEnabled ?? this.keepAliveEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'morningCallEnabled': morningCallEnabled,
        'morningCallTime': morningCallTime,
        'nightSleepEnabled': nightSleepEnabled,
        'nightSleepTime': nightSleepTime,
        'idleChatEnabled': idleChatEnabled,
        'idleChatIntervalHours': idleChatIntervalHours,
        'voiceEnabled': voiceEnabled,
        'keepAliveEnabled': keepAliveEnabled,
      };

  factory RoutineConfig.fromJson(Map<String, dynamic> json) => RoutineConfig(
        morningCallEnabled: json['morningCallEnabled'] as bool? ?? true,
        morningCallTime: json['morningCallTime'] as String? ?? '08:00',
        nightSleepEnabled: json['nightSleepEnabled'] as bool? ?? true,
        nightSleepTime: json['nightSleepTime'] as String? ?? '23:30',
        idleChatEnabled: json['idleChatEnabled'] as bool? ?? true,
        idleChatIntervalHours: (json['idleChatIntervalHours'] as num?)?.toInt() ?? 3,
        voiceEnabled: json['voiceEnabled'] as bool? ?? true,
        keepAliveEnabled: json['keepAliveEnabled'] as bool? ?? true,
      );
}
