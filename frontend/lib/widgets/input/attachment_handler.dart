import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/conversations_provider.dart';
import '../../providers/messaging_provider.dart';
import '../gif_picker_sheet.dart';
import '../top_snackbar.dart';

/// Utility class for file / image / GIF attachment handling.
///
/// Each static method receives a [BuildContext] and delegates to the
/// appropriate provider after gathering recipient / conversation context.
/// All UI error feedback uses [showTopSnackBar].
///
/// Note: Image picking and file picking are already fully implemented in
/// [ChatActionTiles]. This class exposes the core send helpers so they
/// can be reused independently of the action tiles widget.
class AttachmentHandler {
  const AttachmentHandler._();

  // ── image sending ─────────────────────────────────────────────────────────

  /// Sends an image from bytes (already loaded by the caller).
  ///
  /// Uses [MessagingProvider.sendImageMessage] which expects an [XFile].
  static Future<void> sendImage(
    BuildContext context, {
    required Uint8List imageBytes,
    required String filename,
    required String mimeType,
  }) async {
    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();
    final convs = context.read<ConversationsProvider>();

    final conversationId = convs.activeConversationId;
    if (conversationId == null) {
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarNoActiveConversation);
      return;
    }

    final conv = convs.getConversationById(conversationId);
    if (conv == null) return;
    final recipientId = convs.getOtherUserId(conv);

    try {
      final xfile = XFile.fromData(
        kIsWeb ? imageBytes : imageBytes,
        name: filename,
        mimeType: mimeType,
      );
      await messaging.sendImageMessage(auth.token!, xfile, recipientId);
    } catch (e) {
      if (!context.mounted) return;
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarFailedToSendImage);
      debugPrint('AttachmentHandler.sendImage error: $e');
    }
  }

  // ── GIF picker ────────────────────────────────────────────────────────────

  /// Opens the GIF picker sheet and, on selection, calls
  /// [MessagingProvider.sendGif] with the selected Giphy URL.
  static void openGifPicker(BuildContext context) {
    final convs = context.read<ConversationsProvider>();
    final conversationId = convs.activeConversationId;
    if (conversationId == null) {
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarNoActiveConversation);
      return;
    }

    final conv = convs.getConversationById(conversationId);
    if (conv == null) return;
    final recipientId = convs.getOtherUserId(conv);

    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();

    GifPickerSheet.show(
      context,
      onGifSelected: (gifUrl) {
        messaging.sendGif(auth.token!, gifUrl, recipientId);
      },
    );
  }
}
