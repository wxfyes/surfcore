class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String modality;
  final String? audioUrl;
  final String? emojiType;
  final bool isError;
  final bool isPending;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.modality = 'text',
    this.audioUrl,
    this.emojiType,
    this.isError = false,
    this.isPending = false,
  });

  /// 提取过滤掉 [emoji:xxx]、[compare:xxx]、[image:xxx]、[music:xxx] 后的干净文字
  String get displayCleanText {
    var clean = text.replaceAll(RegExp(r'\[emoji:[a-zA-Z0-9_-]+\]'), '');
    clean = clean.replaceAll(RegExp(r'\[compare:[^\]]+\]'), '');
    clean = clean.replaceAll(RegExp(r'\[image:[^\]]+\]'), '');
    clean = clean.replaceAll(RegExp(r'\[music:[^\]]+\]'), '').trim();
    if (clean.isEmpty) {
      if (detectedEmoji != null) return '（发来了一个表情包）';
      if (detectedImageUrl != null) return '（奉上一张自拍画像）';
      if (detectedMusicTitle != null) return '（为你抚琴浅唱）';
    }
    return clean;
  }

  /// 提取识别到的表情包代号
  String? get detectedEmoji {
    if (emojiType != null && emojiType!.isNotEmpty) return emojiType;
    final match = RegExp(r'\[emoji:([a-zA-Z0-9_-]+)\]').firstMatch(text);
    return match?.group(1)?.toLowerCase();
  }

  /// 提取比价关键词（格式形如 [compare:海信电视遥控器]）
  String? get detectedCompareKeyword {
    final match = RegExp(r'\[compare:([^\]]+)\]').firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// 提取图片直链（格式形如 [image:https://...]）
  String? get detectedImageUrl {
    final match = RegExp(r'\[image:(https?://[^\]]+)\]').firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// 提取音乐歌曲名（格式形如 [music:相思引] 或 [music:相思引|https://...]）
  String? get detectedMusicTitle {
    final match = RegExp(r'\[music:([^\|\]]+)(?:\|[^\]]+)?\]').firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// 提取音乐播放音频直链（格式形如 [music:歌名|https://...]）
  String? get detectedMusicUrl {
    final match = RegExp(r'\[music:[^\|\]]+\|([^\]]+)\]').firstMatch(text);
    return match?.group(1)?.trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'modality': modality,
        'audioUrl': audioUrl,
        'emojiType': emojiType ?? detectedEmoji,
        'isError': isError,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        text: json['text'] as String? ?? '',
        isUser: json['isUser'] as bool? ?? false,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
        modality: json['modality'] as String? ?? 'text',
        audioUrl: json['audioUrl'] as String?,
        emojiType: json['emojiType'] as String?,
        isError: json['isError'] as bool? ?? false,
      );

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    String? modality,
    String? audioUrl,
    String? emojiType,
    bool? isError,
    bool? isPending,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      modality: modality ?? this.modality,
      audioUrl: audioUrl ?? this.audioUrl,
      emojiType: emojiType ?? this.emojiType,
      isError: isError ?? this.isError,
      isPending: isPending ?? this.isPending,
    );
  }
}
