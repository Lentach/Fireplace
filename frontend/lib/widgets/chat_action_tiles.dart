import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import '../utils/file_utils_stub.dart' if (dart.library.io) '../utils/file_utils_io.dart' as file_utils;
import '../models/conversation_model.dart';
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/messaging_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../utils/message_expiry.dart';
import 'top_snackbar.dart';
import 'anti_quantum_note_dialog.dart';
import 'gif_picker_sheet.dart';

class ChatActionTiles extends StatelessWidget {
  final double bottomPadding;

  const ChatActionTiles({
    super.key,
    this.bottomPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final borderColor =
        FireplaceColors.of(context).convItemBorder;
    final iconColor = Theme.of(context).colorScheme.primary;

    return Container(
      height: 48 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
          _LongPressActionTile(
            icon: Icons.delete_forever,
            color: iconColor,
            onLongPressComplete: () => _handleClearChatHistory(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.timer_outlined,
            tooltip: l10n.actionTileTimer,
            color: iconColor,
            onTap: () => _showTimerDialog(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.auto_awesome,
            tooltip: l10n.ping,
            color: iconColor,
            onTap: () => _sendPing(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.attach_file,
            tooltip: l10n.attachment,
            color: iconColor,
            onTap: () => _pickAttachment(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.gif_box,
            tooltip: l10n.actionTileGif,
            color: iconColor,
            onTap: () => _openGifPicker(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.science_outlined,
            tooltip: l10n.actionTileAntiQuantumNote,
            color: iconColor,
            onTap: () => _showAntiQuantumNoteDialog(context),
          ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimerDialog(BuildContext context) {
    final initialSeconds =
        context.read<ConversationsProvider>().conversationDisappearingTimer;
    showDialog(
      context: context,
      builder: (ctx) => _TimerDialog(initialSeconds: initialSeconds),
    );
  }

  /// Returns (conv, recipientId) if conversation is active; otherwise shows snackbar and returns null.
  (ConversationModel, int)? _requireActiveConversation(BuildContext context) {
    if (!_ensureHasActiveConversation(context)) return null;
    final convs = context.read<ConversationsProvider>();
    final conv = convs.getConversationById(convs.activeConversationId!);
    if (conv == null) return null;
    return (conv, convs.getOtherUserId(conv));
  }

  void _sendPing(BuildContext context) {
    final result = _requireActiveConversation(context);
    if (result == null) return;
    context.read<MessagingProvider>().sendPing(result.$2);
  }

  /// Single tap opens system picker (gallery / folder). User chooses file; we send as image or document by type.
  Future<void> _pickAttachment(BuildContext context) async {
    final result = _requireActiveConversation(context);
    if (result == null) return;

    final pickResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif',
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv',
      ],
      withData: true,
    );

    if (pickResult == null || pickResult.files.isEmpty || !context.mounted) return;

    final l10n = AppLocalizations.of(context);
    final file = pickResult.files.single;
    List<int> bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (!kIsWeb && file.path != null) {
      bytes = await file_utils.readFileBytes(file.path!);
    } else {
      if (context.mounted) {
        showTopSnackBar(context, l10n.snackbarCouldNotReadFile,
            backgroundColor: Colors.red);
      }
      return;
    }

    if (!context.mounted) return;

    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();
    final recipientId = result.$2;
    final fileName = file.name;
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final isImage = ['jpg', 'jpeg', 'png', 'gif'].contains(ext);

    if (isImage) {
      showTopSnackBar(context, l10n.snackbarUploadingImage);
      try {
        final xfile = XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType: _imageMimeForExtension(ext),
        );
        await messaging.sendImageMessage(auth.token!, xfile, recipientId);
        if (context.mounted) {
          showTopSnackBar(context, l10n.snackbarImageSent);
        }
      } catch (e) {
        if (context.mounted) {
          showTopSnackBar(context, '${l10n.uploadFailed}: $e',
              backgroundColor: Colors.red);
        }
      }
    } else {
      showTopSnackBar(context, l10n.snackbarUploadingDocument);
      try {
        await messaging.sendFileMessage(
          auth.token!,
          bytes,
          fileName,
          _mimeForExtension(ext),
          recipientId,
        );
        if (context.mounted) {
          showTopSnackBar(context, l10n.snackbarDocumentSent);
        }
      } catch (e) {
        if (context.mounted) {
          showTopSnackBar(context, '${l10n.uploadFailed}: $e',
              backgroundColor: Colors.red);
        }
      }
    }
  }

  static String _imageMimeForExtension(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      default: return 'image/jpeg';
    }
  }

  static String _mimeForExtension(String ext) {
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt': return 'text/plain';
      case 'csv': return 'text/csv';
      default: return 'application/octet-stream';
    }
  }

  bool _ensureHasActiveConversation(BuildContext context) {
    if (context.read<ConversationsProvider>().activeConversationId == null) {
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarOpenConversationFirst);
      return false;
    }
    return true;
  }

  void _showAntiQuantumNoteDialog(BuildContext context) {
    final result = _requireActiveConversation(context);
    if (result == null) return;

    final messaging = context.read<MessagingProvider>();
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AntiQuantumNoteDialog(
        onSend: (content, ttl) async {
          try {
            await messaging.sendAntiQuantumNote(
              content: content,
              expiresInSeconds: ttl,
            );
            if (context.mounted) {
              Navigator.of(context).pop();
              showTopSnackBar(context, l10n.antiQuantumNoteSent);
            }
          } catch (e) {
            if (context.mounted) {
              showTopSnackBar(
                context,
                l10n.antiQuantumNoteSendFailed(e.toString()),
                backgroundColor: Colors.red,
              );
            }
          }
        },
      ),
    );
  }

  void _openGifPicker(BuildContext context) {
    final result = _requireActiveConversation(context);
    if (result == null) return;

    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();

    GifPickerSheet.show(
      context,
      onGifSelected: (gifUrl) {
        messaging.sendGif(auth.token!, gifUrl, result.$2);
      },
    );
  }

  void _handleClearChatHistory(BuildContext context) {
    if (!_ensureHasActiveConversation(context)) return;

    final convs = context.read<ConversationsProvider>();
    final messaging = context.read<MessagingProvider>();
    final conversationId = convs.activeConversationId!;

    // Clear chat history
    messaging.clearChatHistory(conversationId);

    // Show success feedback
    if (context.mounted) {
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarChatHistoryDeleted);
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
  OverlayEntry? _progressOverlay;

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
          widget.onLongPressComplete();
          _reset();
        }
      });
  }

  @override
  void dispose() {
    _removeProgressOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeProgressOverlay() {
    _progressOverlay?.remove();
    _progressOverlay = null;
  }

  void _reset() {
    _removeProgressOverlay();
    setState(() {
      _isPressed = false;
      _animationController.reset();
    });
  }

  void _showProgressOverlay() {
    _removeProgressOverlay();
    final overlay = Overlay.of(context);
    final accentColor = Theme.of(context).colorScheme.primary;
    _progressOverlay = OverlayEntry(
      builder: (context) => _CenterProgressOverlay(
        progress: _animationController,
        color: accentColor,
      ),
    );
    overlay.insert(_progressOverlay!);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() => _isPressed = true);
    _animationController.forward();
    _showProgressOverlay();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_animationController.status != AnimationStatus.completed) {
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
        child: Icon(widget.icon, size: 24, color: widget.color),
      ),
    );
  }
}

class _CenterProgressOverlay extends StatelessWidget {
  final Animation<double> progress;
  final Color color;

  const _CenterProgressOverlay({
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(100, 100),
                  painter: _CircularProgressPainter(
                    progress: progress.value,
                    color: color,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).clearingChat,
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerDialog extends StatefulWidget {
  final int? initialSeconds;

  const _TimerDialog({this.initialSeconds});

  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  late final TextEditingController _daysCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _secondsCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final parts = splitDisappearingSeconds(widget.initialSeconds ?? 0);
    _daysCtrl = TextEditingController(text: '${parts.days}');
    _hoursCtrl = TextEditingController(text: '${parts.hours}');
    _minutesCtrl = TextEditingController(text: '${parts.minutes}');
    _secondsCtrl = TextEditingController(text: '${parts.seconds}');
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    super.dispose();
  }

  int _parseField(TextEditingController c) =>
      int.tryParse(c.text.trim()) ?? 0;

  void _apply() {
    final l10n = AppLocalizations.of(context);
    final d = _parseField(_daysCtrl);
    final h = _parseField(_hoursCtrl);
    final m = _parseField(_minutesCtrl);
    final s = _parseField(_secondsCtrl);
    if (d < 0 || h < 0 || m < 0 || s < 0 || h > 23 || m > 59 || s > 59) {
      setState(() => _errorText = l10n.disappearingTimerInvalidFields);
      return;
    }
    final total = combineDisappearingSeconds(
      days: d,
      hours: h,
      minutes: m,
      seconds: s,
    );
    if (total == 0) {
      _submit(null);
      return;
    }
    if (total < kDisappearingMinSeconds || total > kDisappearingMaxSeconds) {
      setState(() => _errorText = l10n.disappearingTimerOutOfRange);
      return;
    }
    _submit(total);
  }

  void _clearError() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  void _submit(int? seconds) {
    final convs = context.read<ConversationsProvider>();
    final convId = convs.activeConversationId;
    if (convId != null) {
      convs.setDisappearingTimer(convId, seconds);
    }
    Navigator.pop(context);
  }

  String _summary(AppLocalizations l10n) {
    final d = _parseField(_daysCtrl);
    final h = _parseField(_hoursCtrl);
    final m = _parseField(_minutesCtrl);
    final s = _parseField(_secondsCtrl);
    final total = combineDisappearingSeconds(
      days: d,
      hours: h,
      minutes: m,
      seconds: s,
    );
    if (total == 0) return l10n.disappearingTimerOff;
    final parts = <String>[];
    if (d > 0) parts.add(l10n.disappearingTimerDays(d));
    if (h > 0) parts.add(l10n.disappearingTimerHours(h));
    if (m > 0) parts.add(l10n.disappearingTimerMinutes(m));
    if (s > 0) parts.add(l10n.disappearingTimerSeconds(s));
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.disappearingTimerTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DurationField(
              label: l10n.disappearingTimerDaysLabel,
              controller: _daysCtrl,
              onChanged: _clearError,
            ),
            _DurationField(
              label: l10n.disappearingTimerHoursLabel,
              controller: _hoursCtrl,
              onChanged: _clearError,
            ),
            _DurationField(
              label: l10n.disappearingTimerMinutesLabel,
              controller: _minutesCtrl,
              onChanged: _clearError,
            ),
            _DurationField(
              label: l10n.disappearingTimerSecondsLabel,
              controller: _secondsCtrl,
              onChanged: _clearError,
            ),
            const SizedBox(height: 12),
            Text(
              _summary(l10n),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _apply,
          child: Text(l10n.disappearingTimerApply),
        ),
      ],
    );
  }
}

class _DurationField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _DurationField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
        ),
        onChanged: (_) => onChanged(),
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
      ..color = Colors.grey.withValues(alpha: 0.3)
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
