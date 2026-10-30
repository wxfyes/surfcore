class PetStatus {
  final bool online;
  final String characterName;
  final String roleDescription;
  final bool isFocusMode;
  final String presenceState;
  final int eventSeq;
  final int serverTime;

  PetStatus({
    this.online = false,
    this.characterName = 'SurfCore AI',
    this.roleDescription = '',
    this.isFocusMode = false,
    this.presenceState = '在线',
    this.eventSeq = 0,
    this.serverTime = 0,
  });

  factory PetStatus.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as Map<String, dynamic>? ?? {};
    final focus = json['focus'] as Map<String, dynamic>? ?? {};
    final presence = json['presence'] as Map<String, dynamic>? ?? {};
    final events = json['events'] as Map<String, dynamic>? ?? {};

    return PetStatus(
      online: json['ok'] == true,
      characterName: role['name'] as String? ?? 'SurfCore AI',
      roleDescription: role['description'] as String? ?? '',
      isFocusMode: focus['enabled'] == true,
      presenceState: presence['state'] as String? ?? '在线',
      eventSeq: events['lastSeq'] as int? ?? 0,
      serverTime: json['serverTime'] as int? ?? 0,
    );
  }
}
