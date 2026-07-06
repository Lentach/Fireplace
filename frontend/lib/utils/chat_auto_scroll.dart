/// Whether the chat list should auto-scroll to the newest message after new
/// rows arrive.
///
/// Own sends ALWAYS scroll (text, emote-panel, media alike — Telegram parity):
/// the sender just acted, so the newest message must be visible even if they
/// had scrolled up. Peer messages scroll only when the user is already near the
/// bottom and has not deliberately scrolled away (otherwise they get the badge).
bool shouldAutoScrollOnNewMessages({
  required int newOwnMessages,
  required bool wasNearBottom,
  required bool userHasScrolledChat,
}) {
  return newOwnMessages > 0 || (wasNearBottom && !userHasScrolledChat);
}
