import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../screens/drawing_canvas_screen.dart';

class ChatActionTiles extends StatelessWidget {
  const ChatActionTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;
    final tileColor = isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;
    final iconColor = isDark ? RpgTheme.accentDark : RpgTheme.primaryLight;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _ActionTile(
            icon: Icons.timer_outlined,
            label: 'Timer',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _showTimerDialog(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.campaign,
            label: 'Ping',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _sendPing(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.camera_alt,
            label: 'Camera',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _openCamera(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.brush,
            label: 'Draw',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _openDrawing(context),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.gif_box,
            label: 'GIF',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _showComingSoon(context, 'GIF picker'),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: Icons.more_horiz,
            label: 'More',
            color: iconColor,
            backgroundColor: tileColor,
            onTap: () => _showComingSoon(context, 'More options'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a conversation first')),
      );
      return;
    }

    final conv = chat.conversations
        .firstWhere((c) => c.id == chat.activeConversationId);
    final recipientId = chat.getOtherUserId(conv);

    chat.sendPing(recipientId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ping sent!')),
    );
  }

  Future<void> _openCamera(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a conversation first')),
      );
      return;
    }

    final conv = chat.conversations
        .firstWhere((c) => c.id == chat.activeConversationId);
    final recipientId = chat.getOtherUserId(conv);

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading image...')),
        );
      }

      try {
        await chat.sendImageMessage(auth.token!, image, recipientId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image sent!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e')),
          );
        }
      }
    }
  }

  void _openDrawing(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a conversation first')),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: RpgTheme.bodyFont(
                fontSize: 10,
                color: color,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerDialog extends StatefulWidget {
  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  int? _selectedSeconds;

  final _options = [
    {'label': '30 seconds', 'value': 30},
    {'label': '1 minute', 'value': 60},
    {'label': '5 minutes', 'value': 300},
    {'label': '1 hour', 'value': 3600},
    {'label': '1 day', 'value': 86400},
    {'label': 'Off', 'value': null},
  ];

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatProvider>();
    _selectedSeconds = chat.conversationDisappearingTimer;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Disappearing Messages'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _options.map((opt) {
          return RadioListTile<int?>(
            title: Text(opt['label'] as String),
            value: opt['value'] as int?,
            groupValue: _selectedSeconds,
            onChanged: (val) {
              setState(() => _selectedSeconds = val);
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final chat = context.read<ChatProvider>();
            chat.setConversationDisappearingTimer(_selectedSeconds);
            Navigator.pop(context);
          },
          child: const Text('Set'),
        ),
      ],
    );
  }
}
