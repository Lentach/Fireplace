/**
 * Pure decision for "should the server SKIP sending a push because the recipient
 * is actively viewing this exact conversation in the foreground".
 *
 * Why a freshness window (the Android-PWA reliability fix): the client reports
 * `clientVisible` via `visibilitychange` / app-lifecycle events, but Android
 * Chrome PWAs miss or delay those on screen-lock / backgrounding. A stale
 * `clientVisible: true` then wrongly suppresses the push — the WebSocket still
 * delivers `newMessage` (so the in-app badge updates) but no notification is
 * ever shown ("badge yes, notification no"). A genuinely-foreground client
 * heartbeats this state, so we only honour the foreground claim when it was
 * refreshed within [freshMs]; otherwise we send the push (a redundant heads-up
 * for someone truly viewing the chat is far better than a missed message).
 */
export interface PushClientState {
  activeConversationId?: number | null;
  clientVisible?: boolean;
  /** Server-side receipt time (ms) of the last pushClientState report. */
  updatedAt?: number;
}

export function shouldSuppressPushForFocusedState(
  state: PushClientState | undefined,
  conversationId: number,
  now: number,
  freshMs: number,
): boolean {
  if (!state) return false;
  if (!state.clientVisible) return false;
  if (state.activeConversationId !== conversationId) return false;
  // Treat a missing or stale timestamp as "not currently verified foreground".
  const updatedAt = state.updatedAt ?? 0;
  if (now - updatedAt > freshMs) return false;
  return true;
}
