import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../models/message_model.dart';

/// Human-readable body text for a message bubble: maps the E2E placeholder
/// sentinels to localized strings, else the decrypted plaintext, else an
/// unsupported-type fallback.
///
/// Pure (reads Localizations only, no Provider) so both [ChatMessageBubble] and
/// the context-menu replica (which mounts provider-free in an Overlay) share one
/// source of truth.
String messageDisplayContent(BuildContext context, MessageModel message) {
  final l10n = AppLocalizations.of(context);
  if (message.content == '[Decryption failed]') return l10n.decryptionFailed;
  if (message.content == '[Encryption not initialized]') {
    return l10n.encryptionNotInitialized;
  }
  if (message.content.isNotEmpty) return message.content;
  return l10n.unsupportedMessageType;
}
