import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/file_utils_stub.dart'
    if (dart.library.io) '../utils/file_utils_io.dart'
    as file_utils;
import '../models/conversation_model.dart';
import '../utils/attachment_picker_stub.dart'
    if (dart.library.html) '../utils/attachment_picker_web.dart'
    as attachment_picker;
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/messaging_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/glass_theme.dart';
import 'glass/glass_sheet.dart';
import 'glass/glass_surface.dart';
import '../theme/rpg_theme.dart';
import 'input/focus_guard_area.dart';
export 'disappearing_timer_sheet.dart';
import 'disappearing_timer_sheet.dart';
import 'top_snackbar.dart';
import 'anti_quantum_note_dialog.dart';
import 'gif_picker_sheet.dart';
import 'ping_glyph.dart';

/// Stages a picked image into the composer (existing staged-image flow).
typedef StageImageCallback =
    void Function({
      required Uint8List bytes,
      required String mimeType,
      required String filename,
    });

/// Stages a picked video into the composer (staged-video flow; policy checks
/// and rejection toasts happen inside).
typedef StageVideoCallback =
    Future<void> Function({required Uint8List bytes, required String filename});

class ChatActionTiles extends StatelessWidget {
  final double bottomPadding;

  /// Fired after a ping send so the composer can restore keyboard focus.
  /// Ping is keyboard-neutral (user ruling 2026-07-09): on iOS WebKit the
  /// [FocusGuardArea] below stops the tap's DOM blur outright; off iOS the
  /// composer heals the blur post-frame through this callback.
  final VoidCallback? onPingSent;

  /// Composer staging seams (null only in standalone test mounts —
  /// [_routePickedFile]'s media branches then no-op per branch; the
  /// document branch is seam-free and still works). Media routes by
  /// extension: image → staged-image flow, video → staged-video flow.
  final StageImageCallback? onStageImage;
  final StageVideoCallback? onStageVideo;

  const ChatActionTiles({
    super.key,
    this.bottomPadding = 0,
    this.onPingSent,
    this.onStageImage,
    this.onStageVideo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final iconColor = GlassTheme.of(context).onGlassAccent;
    final convs = context.watch<ConversationsProvider>();
    final timerActive = convs.conversationDisappearingTimer != null;

    // Liquid Glass: the panel is a floating glass pill matching the composer
    // pill footprint; total height (56 + insets + bottomPadding) stays a
    // plain function of layout so the composer viewport measures it as
    // before. Glass is paint, not layout.
    //
    // The transparent gutter around the pill must still HIT-TEST as part of
    // the composer tap region: a mis-tap 4px off the pill edge must not
    // dismiss the keyboard (the exact iOS jank class fixed in 0.0.93-0.0.99).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Hit-test shim only — never an announced control.
      excludeFromSemantics: true,
      onTap: () {},
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + bottomPadding),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(28),
          height: 56,
          shadow: false,
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: box.maxWidth - 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LongPressActionTile(
                      icon: Icons.delete_forever,
                      color: iconColor,
                      onLongPressComplete: () =>
                          _handleClearChatHistory(context),
                    ),
                    const SizedBox(width: 12),
                    _ActionTile(
                      icon: Icons.hourglass_bottom_outlined,
                      tooltip: l10n.actionTileDisappearingMessages,
                      color: iconColor,
                      showBadge: timerActive,
                      onTap: () => _showTimerDialog(context),
                    ),
                    const SizedBox(width: 12),
                    FocusGuardArea(
                      id: 'action_tile_ping',
                      child: _ActionTile(
                        customIcon: PingGlyph(size: 24, color: iconColor),
                        tooltip: l10n.ping,
                        color: iconColor,
                        onTap: () => _sendPing(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Builder(
                      builder: (tileContext) => _ActionTile(
                        icon: Icons.attach_file,
                        tooltip: l10n.attachment,
                        color: iconColor,
                        onTap: () => _pickAttachment(context, tileContext),
                      ),
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
          ),
        ),
      ),
    );
  }

  void _showTimerDialog(BuildContext context) {
    showDisappearingTimerSheet(context);
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
    onPingSent?.call();
  }

  static const _galleryImageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  static const _galleryVideoExtensions = ['mp4', 'm4v', 'mov'];
  static const _documentExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'txt',
    'csv',
  ];

  /// Paperclip door — ONE bare file input, no in-app sheet (owner ruling
  /// 2026-08-17, device-proven): on iOS a plain input with this mixed accept
  /// list makes Safari itself present Photo Library / Take Photo or Video /
  /// Choose File — camera toggle included — so an in-app chooser is a
  /// redundant hop. Android/desktop open their system picker (Android loses
  /// the in-chat camera shortcut; accepted trade-off, iOS-first). The result
  /// routes by extension: image/video STAGE (send button sends), documents
  /// send immediately.
  ///
  /// On web the input is POSITIONED at the paperclip tile's rect
  /// ([tileContext]) so iOS anchors the picker popover to the tile instead
  /// of centering it mid-screen — Flutter taps carry no DOM interaction
  /// Safari could anchor to (probe3, 2026-08-17). Off web, FilePicker.
  Future<void> _pickAttachment(
    BuildContext context,
    BuildContext tileContext,
  ) async {
    if (_requireActiveConversation(context) == null) return;

    String fileName;
    List<int>? bytes;
    if (kIsWeb) {
      final box = tileContext.findRenderObject() as RenderBox?;
      final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
      final size = box?.size ?? Size.zero;
      final picked = await attachment_picker.pickAttachmentFileAt(
        left: origin.dx,
        top: origin.dy,
        width: size.width,
        height: size.height,
        accept: [
          ..._galleryImageExtensions,
          ..._galleryVideoExtensions,
          ..._documentExtensions,
        ].map((e) => '.$e').join(','),
      );
      if (picked == null) return;
      fileName = picked.name;
      bytes = picked.bytes;
    } else {
      final pickResult = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          ..._galleryImageExtensions,
          ..._galleryVideoExtensions,
          ..._documentExtensions,
        ],
        withData: true,
      );
      if (pickResult == null || pickResult.files.isEmpty) return;
      final file = pickResult.files.single;
      fileName = file.name;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await file_utils.readFileBytes(file.path!);
      }
    }

    if (!context.mounted) return;
    await _routePickedFile(context, fileName: fileName, bytes: bytes);
  }

  /// Routes a picked file by extension. Routing is EXPLICIT: whitelisted
  /// image extensions stage as image, video extensions stage as video
  /// (media staging no-ops in callback-less test mounts), document
  /// extensions send immediately, and anything else (e.g. an iOS HEIC the
  /// device did not transcode) gets an honest unsupported-file toast —
  /// never a video-shaped error for an image.
  Future<void> _routePickedFile(
    BuildContext context, {
    required String fileName,
    required List<int>? bytes,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (bytes == null) {
      showTopSnackBar(
        context,
        l10n.snackbarCouldNotReadFile,
        backgroundColor: Colors.red,
      );
      return;
    }
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (_galleryImageExtensions.contains(ext)) {
      if (onStageImage == null) return;
      onStageImage!(
        bytes: Uint8List.fromList(bytes),
        mimeType: _imageMimeForExtension(ext),
        filename: fileName,
      );
      return;
    }
    if (_galleryVideoExtensions.contains(ext)) {
      if (onStageVideo == null) return;
      await onStageVideo!(bytes: Uint8List.fromList(bytes), filename: fileName);
      return;
    }
    if (_documentExtensions.contains(ext)) {
      await _sendDocument(context, fileName: fileName, bytes: bytes);
      return;
    }
    showTopSnackBar(
      context,
      l10n.attachmentUnsupportedFileType,
      backgroundColor: Colors.red,
    );
  }

  /// Document branch: always [MessagingProvider.sendFileMessage] — never
  /// image routing. Sends immediately (documents do not stage).
  Future<void> _sendDocument(
    BuildContext context, {
    required String fileName,
    required List<int> bytes,
  }) async {
    final result = _requireActiveConversation(context);
    if (result == null) return;

    final l10n = AppLocalizations.of(context);
    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    showTopSnackBar(context, l10n.snackbarUploadingDocument);
    try {
      await messaging.sendFileMessage(
        auth.token!,
        bytes,
        fileName,
        _mimeForExtension(ext),
        result.$2,
      );
      if (context.mounted) {
        showTopSnackBar(context, l10n.snackbarDocumentSent);
      }
    } catch (e) {
      if (context.mounted) {
        showTopSnackBar(
          context,
          '${l10n.uploadFailed}: $e',
          backgroundColor: Colors.red,
        );
      }
    }
  }


  static String _imageMimeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'image/jpeg';
    }
  }

  static String _mimeForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  bool _ensureHasActiveConversation(BuildContext context) {
    if (context.read<ConversationsProvider>().activeConversationId == null) {
      showTopSnackBar(
        context,
        AppLocalizations.of(context).snackbarOpenConversationFirst,
      );
      return false;
    }
    return true;
  }

  void _showAntiQuantumNoteDialog(BuildContext context) {
    final result = _requireActiveConversation(context);
    if (result == null) return;

    final messaging = context.read<MessagingProvider>();
    final l10n = AppLocalizations.of(context);

    showGlassSheet<void>(
      context,
      isScrollControlled: true,
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
                backgroundColor: Theme.of(context).colorScheme.error,
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
        context,
        AppLocalizations.of(context).snackbarChatHistoryDeleted,
      );
    }

    // Close action panel (navigate back if possible)
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}


class _ActionTile extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool showBadge;

  const _ActionTile({
    this.icon,
    this.customIcon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.showBadge = false,
  }) : assert((icon == null) != (customIcon == null));

  @override
  Widget build(BuildContext context) {
    final badgeColor = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: customIcon ?? Icon(icon, size: 24, color: color),
              ),
              if (showBadge)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
    // No per-frame listener here: build() renders a static icon and reads
    // nothing controller-derived. The visible progress ring is painted by the
    // overlay's own AnimatedBuilder, so a setState listener was ~90 wasted
    // rebuilds per 1500 ms gesture.
    _animationController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1500),
          )
          ..addStatusListener((status) {
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

  const _CenterProgressOverlay({required this.progress, required this.color});

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
              style: RpgTheme.bodyFont(fontSize: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color color;

  _CircularProgressPainter({required this.progress, required this.color});

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
