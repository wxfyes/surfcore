import 'package:flutter/material.dart';

class EmojiSticker extends StatefulWidget {
  final String emojiCode;

  const EmojiSticker({super.key, required this.emojiCode});

  @override
  State<EmojiSticker> createState() => _EmojiStickerState();
}

class _EmojiStickerState extends State<EmojiSticker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  EmojiMeta _getMeta(String code) {
    switch (code.toLowerCase()) {
      case 'hug':
        return const EmojiMeta(
          icon: Icons.favorite_rounded,
          emojiChar: '🫂',
          label: '扑进怀里求抱抱',
          accentColor: Color(0xFFFF6584),
          gradient: [Color(0xFFFFE3E8), Color(0xFFFFC2D1)],
        );
      case 'shy':
        return const EmojiMeta(
          icon: Icons.sentiment_satisfied_alt_rounded,
          emojiChar: '🙈',
          label: '哎呀~害羞死啦',
          accentColor: Color(0xFFFF7597),
          gradient: [Color(0xFFFFF0F3), Color(0xFFFFD6E0)],
        );
      case 'kiss':
        return const EmojiMeta(
          icon: Icons.volunteer_activism_rounded,
          emojiChar: '💋',
          label: '么么哒~亲亲老公',
          accentColor: Color(0xFFF43F5E),
          gradient: [Color(0xFFFFE4E6), Color(0xFFFECDD3)],
        );
      case 'heart':
        return const EmojiMeta(
          icon: Icons.favorite_rounded,
          emojiChar: '💖',
          label: '超级超级爱你呀',
          accentColor: Color(0xFFEC4899),
          gradient: [Color(0xFFFCE7F3), Color(0xFFFBCFE8)],
        );
      case 'cheer':
        return const EmojiMeta(
          icon: Icons.auto_awesome_rounded,
          emojiChar: '✨',
          label: '老公加油工作呀！',
          accentColor: Color(0xFFEAB308),
          gradient: [Color(0xFFFEF9C3), Color(0xFFFEF08A)],
        );
      case 'pout':
        return const EmojiMeta(
          icon: Icons.sentiment_dissatisfied_rounded,
          emojiChar: '🥺',
          label: '假装吃醋噘嘴嘴',
          accentColor: Color(0xFFF97316),
          gradient: [Color(0xFFFFEDD5), Color(0xFFFED7AA)],
        );
      case 'sleep':
        return const EmojiMeta(
          icon: Icons.bedtime_rounded,
          emojiChar: '🌙',
          label: '困困了，要抱抱睡',
          accentColor: Color(0xFF8B5CF6),
          gradient: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
        );
      case 'pat':
        return const EmojiMeta(
          icon: Icons.pets_rounded,
          emojiChar: '🥰',
          label: '摸摸头心疼老公',
          accentColor: Color(0xFF06B6D4),
          gradient: [Color(0xFFCFFAFE), Color(0xFFA5F3FC)],
        );
      case 'water':
        return const EmojiMeta(
          icon: Icons.local_cafe_rounded,
          emojiChar: '🍵',
          label: '老公辛苦了喝口水',
          accentColor: Color(0xFF10B981),
          gradient: [Color(0xFFD1FAE5), Color(0xFFA7F3D0)],
        );
      case 'daze':
      default:
        return const EmojiMeta(
          icon: Icons.help_center_rounded,
          emojiChar: '❓',
          label: '呆萌眨巴大眼睛',
          accentColor: Color(0xFF6366F1),
          gradient: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _getMeta(widget.emojiCode);

    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: meta.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: meta.accentColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: meta.accentColor.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.75),
                boxShadow: [
                  BoxShadow(
                    color: meta.accentColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                meta.icon,
                size: 32,
                color: meta.accentColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(meta.icon, size: 12, color: meta.accentColor),
                const SizedBox(width: 4),
                Text(
                  meta.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: meta.accentColor.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmojiMeta {
  final IconData icon;
  final String emojiChar;
  final String label;
  final Color accentColor;
  final List<Color> gradient;

  const EmojiMeta({
    required this.icon,
    required this.emojiChar,
    required this.label,
    required this.accentColor,
    required this.gradient,
  });
}
