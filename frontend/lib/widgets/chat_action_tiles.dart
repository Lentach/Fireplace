import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
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
    final convs = context.read<ConversationsProvider>();
    final initialSeconds = convs.conversationDisappearingTimer;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ChangeNotifierProvider<ConversationsProvider>.value(
        value: convs,
        child: DisappearingTimerSheet(initialSeconds: initialSeconds),
      ),
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

const double _kDisappearingPickerHeight = 216;
const double _kDisappearingPickerItemExtent = 32;
const int _kDisappearingPickerMaxDays = 30;

/// iOS-style D/H/M/S scroll wheels for conversation disappearing timer.
class DisappearingTimerSheet extends StatefulWidget {
  final int? initialSeconds;

  const DisappearingTimerSheet({super.key, this.initialSeconds});

  @override
  State<DisappearingTimerSheet> createState() => _DisappearingTimerSheetState();
}

class _DisappearingTimerSheetState extends State<DisappearingTimerSheet> {
  late int _days;
  late int _hours;
  late int _minutes;
  late int _seconds;
  late final FixedExtentScrollController _daysController;
  late final FixedExtentScrollController _hoursController;
  late final FixedExtentScrollController _minutesController;
  late final FixedExtentScrollController _secondsController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final parts = splitDisappearingSeconds(widget.initialSeconds ?? 0);
    _days = parts.days.clamp(0, _kDisappearingPickerMaxDays);
    _hours = parts.hours.clamp(0, 23);
    _minutes = parts.minutes.clamp(0, 59);
    _seconds = parts.seconds.clamp(0, 59);
    _daysController = FixedExtentScrollController(initialItem: _days);
    _hoursController = FixedExtentScrollController(initialItem: _hours);
    _minutesController = FixedExtentScrollController(initialItem: _minutes);
    _secondsController = FixedExtentScrollController(initialItem: _seconds);
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  int get _totalSeconds => combineDisappearingSeconds(
        days: _days,
        hours: _hours,
        minutes: _minutes,
        seconds: _seconds,
      );

  void _apply() {
    final l10n = AppLocalizations.of(context);
    final total = _totalSeconds;
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

  void _submit(int? seconds) {
    final convs = context.read<ConversationsProvider>();
    final convId = convs.activeConversationId;
    if (convId != null) {
      convs.setDisappearingTimer(convId, seconds);
    }
    Navigator.pop(context);
  }

  String _summary(AppLocalizations l10n) {
    final total = _totalSeconds;
    if (total == 0) return l10n.disappearingTimerOff;
    final parts = <String>[];
    if (_days > 0) parts.add(l10n.disappearingTimerDays(_days));
    if (_hours > 0) parts.add(l10n.disappearingTimerHours(_hours));
    if (_minutes > 0) parts.add(l10n.disappearingTimerMinutes(_minutes));
    if (_seconds > 0) parts.add(l10n.disappearingTimerSeconds(_seconds));
    return parts.join(' ');
  }

  void _onDaysChanged(int index) {
    setState(() {
      _days = index;
      _errorText = null;
    });
  }

  void _onHoursChanged(int index) {
    setState(() {
      _hours = index;
      _errorText = null;
    });
  }

  void _onMinutesChanged(int index) {
    setState(() {
      _minutes = index;
      _errorText = null;
    });
  }

  void _onSecondsChanged(int index) {
    setState(() {
      _seconds = index;
      _errorText = null;
    });
  }

  Widget _columnLabel(String label, Color color) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _durationPicker({
    required String semanticsLabel,
    required int maxValue,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onSelectedItemChanged,
  }) {
    return Expanded(
      child: Semantics(
        label: semanticsLabel,
        child: CupertinoPicker(
          scrollController: controller,
          itemExtent: _kDisappearingPickerItemExtent,
          magnification: 1.1,
          squeeze: 1.1,
          useMagnifier: true,
          onSelectedItemChanged: onSelectedItemChanged,
          children: List<Widget>.generate(
            maxValue + 1,
            (i) => Center(child: Text('$i')),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final sheetColor = isDark
        ? const Color(0xFF1C1C1E)
        : CupertinoColors.systemBackground.resolveFrom(context);
    final labelColor = isDark
        ? CupertinoColors.secondaryLabel.darkColor
        : CupertinoColors.secondaryLabel.color;
    final titleColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    final summaryColor = isDark
        ? CupertinoColors.secondaryLabel.darkColor
        : CupertinoColors.secondaryLabel.color;

    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(
        brightness: brightness,
        textTheme: CupertinoTextThemeData(
          pickerTextStyle: TextStyle(
            fontSize: 22,
            color: titleColor,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: sheetColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          onPressed: () => Navigator.pop(context),
                          child: Text(l10n.cancel),
                        ),
                        Expanded(
                          child: Text(
                            l10n.disappearingTimerTitle,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          onPressed: _apply,
                          child: Text(l10n.disappearingTimerApply),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _summary(l10n),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: summaryColor),
                      ),
                    ),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        _columnLabel(
                          l10n.disappearingTimerDaysLabel,
                          labelColor,
                        ),
                        _columnLabel(
                          l10n.disappearingTimerHoursLabel,
                          labelColor,
                        ),
                        _columnLabel(
                          l10n.disappearingTimerMinutesLabel,
                          labelColor,
                        ),
                        _columnLabel(
                          l10n.disappearingTimerSecondsLabel,
                          labelColor,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: _kDisappearingPickerHeight,
                    child: Row(
                      children: [
                        _durationPicker(
                          semanticsLabel: l10n.disappearingTimerDaysLabel,
                          maxValue: _kDisappearingPickerMaxDays,
                          controller: _daysController,
                          onSelectedItemChanged: _onDaysChanged,
                        ),
                        _durationPicker(
                          semanticsLabel: l10n.disappearingTimerHoursLabel,
                          maxValue: 23,
                          controller: _hoursController,
                          onSelectedItemChanged: _onHoursChanged,
                        ),
                        _durationPicker(
                          semanticsLabel: l10n.disappearingTimerMinutesLabel,
                          maxValue: 59,
                          controller: _minutesController,
                          onSelectedItemChanged: _onMinutesChanged,
                        ),
                        _durationPicker(
                          semanticsLabel: l10n.disappearingTimerSecondsLabel,
                          maxValue: 59,
                          controller: _secondsController,
                          onSelectedItemChanged: _onSecondsChanged,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
        ),
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
