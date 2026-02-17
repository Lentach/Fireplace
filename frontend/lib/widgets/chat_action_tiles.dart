import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/conversation_model.dart';
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
          _LongPressActionTile(
            icon: Icons.delete_forever,
            color: iconColor,
            onLongPressComplete: () => _handleClearChatHistory(context),
          ),
          const SizedBox(width: 12),
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

  /// Returns (conv, recipientId) if conversation is active; otherwise shows snackbar and returns null.
  (ConversationModel, int)? _requireActiveConversation(BuildContext context) {
    if (!_ensureHasActiveConversation(context)) return null;
    final chat = context.read<ChatProvider>();
    final conv = chat.getConversationById(chat.activeConversationId!);
    if (conv == null) return null;
    return (conv, chat.getOtherUserId(conv));
  }

  void _sendPing(BuildContext context) {
    final result = _requireActiveConversation(context);
    if (result == null) return;
    context.read<ChatProvider>().sendPing(result.$2);
  }

  Future<void> _pickAttachment(BuildContext context) async {
    final result = _requireActiveConversation(context);
    if (result == null) return;

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();
    final recipientId = result.$2;

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

  bool _ensureHasActiveConversation(BuildContext context) {
    if (context.read<ChatProvider>().activeConversationId == null) {
      showTopSnackBar(context, 'Open a conversation first');
      return false;
    }
    return true;
  }

  void _openDrawing(BuildContext context) {
    if (!_ensureHasActiveConversation(context)) return;

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

  void _handleClearChatHistory(BuildContext context) {
    if (!_ensureHasActiveConversation(context)) return;

    final chat = context.read<ChatProvider>();
    final conversationId = chat.activeConversationId!;

    // Clear chat history
    chat.clearChatHistory(conversationId);

    // Show success feedback
    if (context.mounted) {
      showTopSnackBar(context, 'Chat history deleted');
    }

    // Close action panel (navigate back if possible)
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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

class _LongPressActionTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onLongPressComplete;

  const _LongPressActionTile({
    required this.icon,
    required this.color,
    required this.onLongPressComplete,
  });

  @override
  State<_LongPressActionTile> createState() => _LongPressActionTileState();
}

class _LongPressActionTileState extends State<_LongPressActionTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(() {
        setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed && _isPressed) {
          // Animation completed while still pressing → trigger action
          widget.onLongPressComplete();
          _reset();
        }
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _isPressed = false;
      _animationController.reset();
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isPressed = true;
    });
    _animationController.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_animationController.status != AnimationStatus.completed) {
      // Released before completion → cancel
      _reset();
    }
  }

  void _onLongPressCancel() {
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Progress ring
            if (_isPressed)
              CustomPaint(
                size: const Size(40, 40),
                painter: _CircularProgressPainter(
                  progress: _animationController.value,
                  color: Colors.red,
                ),
              ),
            // Icon
            Icon(widget.icon, size: 24, color: widget.color),
          ],
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

class _CircularProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color color;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle (light gray)
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc (red)
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * 3.14159 * progress; // Full circle = 2π
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // Start at top (-90 degrees)
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
