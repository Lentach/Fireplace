import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../screens/drawing_canvas_screen.dart';
import 'top_snackbar.dart';

class ChatActionTiles extends StatelessWidget {
  const ChatActionTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;
    final iconColor = isDark ? RpgTheme.accentDark : RpgTheme.primaryLight;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionTile(
            icon: Icons.timer_outlined,
            tooltip: 'Timer',
            color: iconColor,
            onTap: () => _showTimerDialog(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.auto_awesome,
            tooltip: 'Ping',
            color: iconColor,
            onTap: () => _sendPing(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.attach_file,
            tooltip: 'Attachment',
            color: iconColor,
            onTap: () => _pickAttachment(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.brush,
            tooltip: 'Draw',
            color: iconColor,
            onTap: () => _openDrawing(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.gif_box,
            tooltip: 'GIF',
            color: iconColor,
            onTap: () => _showComingSoon(context, 'GIF picker'),
          ),
        ],
      ),
    );
  }

  void _showTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _TimerDialog(),
    );
  }

  void _sendPing(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      showTopSnackBar(context, 'Open a conversation first');
      return;
    }

    final conv = chat.conversations
        .firstWhere((c) => c.id == chat.activeConversationId);
    final recipientId = chat.getOtherUserId(conv);

    chat.sendPing(recipientId);

    showTopSnackBar(context, 'Ping sent!');
  }

  Future<void> _pickAttachment(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      showTopSnackBar(context, 'Open a conversation first');
      return;
    }

    final conv = chat.conversations
        .firstWhere((c) => c.id == chat.activeConversationId);
    final recipientId = chat.getOtherUserId(conv);

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // Show loading indicator
      if (context.mounted) {
        showTopSnackBar(context, 'Uploading image...');
      }

      try {
        await chat.sendImageMessage(auth.token!, image, recipientId);
        if (context.mounted) {
          showTopSnackBar(context, 'Image sent!');
        }
      } catch (e) {
        if (context.mounted) {
          showTopSnackBar(context, 'Upload failed: $e', backgroundColor: Colors.red);
        }
      }
    }
  }

  void _openDrawing(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      showTopSnackBar(context, 'Open a conversation first');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DrawingCanvasScreen(),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    showTopSnackBar(context, '$feature coming soon');
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}

class _TimerDialog extends StatelessWidget {
  final _options = const [
    {'label': '30 seconds', 'value': 30},
    {'label': '1 minute', 'value': 60},
    {'label': '5 minutes', 'value': 300},
    {'label': '1 hour', 'value': 3600},
    {'label': '1 day', 'value': 86400},
    {'label': 'Off', 'value': null},
  ];

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatProvider>();
    final current = chat.conversationDisappearingTimer;

    return AlertDialog(
      title: const Text('Disappearing Messages'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _options.map((opt) {
          final value = opt['value'] as int?;
          final isSelected = value == current;
          return RadioListTile<int?>(
            title: Text(opt['label'] as String),
            value: value,
            groupValue: current,
            onChanged: (_) {
              chat.setConversationDisappearingTimer(value);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}
