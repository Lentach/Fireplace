import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../providers/chat_provider.dart';

class MessageInputBar extends StatefulWidget {
  const MessageInputBar({super.key});

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    context.read<ChatProvider>().sendMessage(content);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            style: RpgTheme.pressStart2P(fontSize: 9, color: Colors.white),
            decoration: RpgTheme.rpgInputDecoration(hintText: 'Type your message...'),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _send,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: RpgTheme.buttonBg,
              border: Border.all(color: RpgTheme.gold, width: 3),
            ),
            child: Text(
              'SEND',
              style: RpgTheme.pressStart2P(fontSize: 9, color: RpgTheme.gold),
            ),
          ),
        ),
      ],
    );
  }
}
