import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class ConversationItem extends StatefulWidget {
  final String email;
  final bool isActive;
  final VoidCallback onTap;

  const ConversationItem({
    super.key,
    required this.email,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<ConversationItem> createState() => _ConversationItemState();
}

class _ConversationItemState extends State<ConversationItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    Color borderColor = RpgTheme.convItemBorder;
    Color textColor = RpgTheme.labelText;
    Color bg = RpgTheme.convItemBg;

    if (widget.isActive) {
      borderColor = RpgTheme.gold;
      textColor = RpgTheme.gold;
      bg = const Color(0xFF2A2A6E);
    } else if (_hovering) {
      borderColor = RpgTheme.purple;
      textColor = Colors.white;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Text(
            widget.email,
            style: RpgTheme.pressStart2P(fontSize: 7, color: textColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
