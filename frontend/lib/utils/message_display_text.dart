import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../models/message_model.dart';
import '../providers/messaging_provider.dart'
    show
        kDecryptionFailedLabel,
        kEncryptedPlaceholderLabel,
        kEncryptionNotInitializedLabel,
        kRetiredMessageLabel;

/// The localized sentence for a row whose CONTENT is an internal sentinel, or
/// null when the row carries real content that must not be touched.
///
/// THE single decision of how a sentinel renders. Two surfaces draw a message
/// body — the bubble (`TextMessageContent._displayBody`) and the provider-free
/// context-menu replica — and before this existed they disagreed: the replica
/// localized `[Decryption failed]` while the bubble printed the raw sentinel
/// (live QA 2026-08-31). Anything added here reaches both; anything added to
/// only one of them drifts.
///
/// [isMine] and [decryptInProgress] are what the bubble knows and the replica
/// does not, so they default to the safe "no relabel" values.
String? sentinelDisplayText(
  BuildContext context,
  MessageModel message, {
  bool isMine = false,
  bool decryptInProgress = false,
}) {
  // Resolved LAZILY per branch, NEVER hoisted: a row carrying real content must
  // render without an [AppLocalizations] ancestor. Hoisting it made every plain
  // text bubble depend on the delegate and crashed `bubble_redesign_test.dart`
  // on a null check — twice, once here and once in the bubble before this
  // mapping moved in.
  final content = message.content;
  if (content == kRetiredMessageLabel) {
    return AppLocalizations.of(context).messageNoLongerStoredOnThisDevice;
  }
  if (content == kEncryptionNotInitializedLabel) {
    return AppLocalizations.of(context).encryptionNotInitialized;
  }
  // Still working on it: it WILL resolve. Keeps the model's own predicate, so a
  // row with no ciphertext never claims to be waiting on the pass.
  if (decryptInProgress && message.displayAsEncryptedPlaceholder) {
    return AppLocalizations.of(context).decryptingMessage;
  }
  // Tried and terminally lost. The post-retry sweep writes this label, so by
  // the time a row carries it the pass is done with it.
  if (content == kDecryptionFailedLabel) {
    return AppLocalizations.of(context).messageUnreadableOnThisDevice;
  }
  // An OWN row is never Signal-decrypted — a sender cannot decrypt its own
  // ciphertext — so its plaintext exists ONLY in the local cache. Once that is
  // gone (wipe, reinstall, cache clear) no pass will ever resolve it, and it
  // never carries the failed label because it never failed a decrypt. This is
  // the row a user sees above their own messages after reinstalling.
  //
  // Keyed on the LITERAL, not `displayAsEncryptedPlaceholder`: that predicate
  // requires ciphertext and a fan-out row carries none for its own origin
  // device (amendment (ix)), so it misses exactly this row.
  //
  // Deliberately NOT extended to PEER rows: a peer `[encrypted]` may simply be
  // awaiting the pass (the frame before `decryptInProgress` goes true would
  // flash a false "can't be read"), and an unresolved peer row is rewritten to
  // `[Decryption failed]` by the sweep above anyway.
  if (!decryptInProgress && isMine && content == kEncryptedPlaceholderLabel) {
    return AppLocalizations.of(context).messageUnreadableOnThisDevice;
  }
  return null;
}

/// Human-readable body text for a message bubble: the sentinel mapping above,
/// else the decrypted plaintext, else an unsupported-type fallback.
///
/// Pure (reads Localizations only, no Provider) so both [ChatMessageBubble] and
/// the context-menu replica (which mounts provider-free in an Overlay) share one
/// source of truth.
String messageDisplayContent(
  BuildContext context,
  MessageModel message, {
  bool isMine = false,
  bool decryptInProgress = false,
}) {
  final mapped = sentinelDisplayText(
    context,
    message,
    isMine: isMine,
    decryptInProgress: decryptInProgress,
  );
  if (mapped != null) return mapped;
  if (message.content.isNotEmpty) return message.content;
  return AppLocalizations.of(context).unsupportedMessageType;
}
