import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ChatProvider>().sendMessage(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor =
        isDark ? RpgTheme.convItemBorder : RpgTheme.convItemBorderLight;
    final inputBg = isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;
    final tabBorderColor =
        isDark ? RpgTheme.tabBorder : RpgTheme.tabBorderLight;
    final sendIconColor = _hasText
        ? (isDark ? RpgTheme.gold : Colors.white)
        : (isDark ? RpgTheme.mutedText : RpgTheme.textSecondaryLight);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: tabBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: tabBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: RpgTheme.primaryColor(context),
                      width: 1.5,
                    ),
                  ),
                  filled: true,
                  fillColor: inputBg,
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RpgTheme.primaryColor(context),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.send_rounded,
                  color: sendIconColor,
                  size: 22,
                ),
                onPressed: _hasText ? _send : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
