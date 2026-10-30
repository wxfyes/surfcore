import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import 'emoji_sticker.dart';
import 'compare_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String characterName;

  const MessageBubble({
    super.key,
    required this.message,
    this.characterName = 'AI',
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _buildAvatar(isUser: false, name: characterName),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF2563EB) // 精致科技蓝
                        : (message.isError
                            ? const Color(0xFFFEE2E2)
                            : Theme.of(context).cardColor),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: message.isPending
                      ? _buildThinkingIndicator()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.displayCleanText.isNotEmpty &&
                                message.displayCleanText != '（发来了一个表情包）')
                              SelectableText(
                                message.displayCleanText,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.45,
                                  color: isUser
                                      ? Colors.white
                                      : (message.isError
                                          ? const Color(0xFFDC2626)
                                          : Theme.of(context).textTheme.bodyLarge?.color),
                                ),
                              ),
                            if (message.detectedEmoji != null)
                              EmojiSticker(emojiCode: message.detectedEmoji!),
                            if (message.detectedCompareKeyword != null)
                              CompareCard(keyword: message.detectedCompareKeyword!),
                          ],
                        ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(isUser: true, name: '我'),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isUser, required String name}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isUser
              ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
              : [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          isUser ? '我' : (name.isNotEmpty ? name.characters.first : 'A'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '正在思考回复...',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
