import { Server, Socket } from 'socket.io';

/**
 * Per-user Socket.IO room. Every authenticated socket joins this on connect
 * (`ChatGateway.handleConnection`), so a user with several tabs open has
 * several sockets in one room.
 *
 * Addressing realtime events by ROOM rather than by a single socket id is
 * load-bearing (BE-007). The gateway used to keep a `Map<userId, socketId>`
 * and emit to `onlineUsers.get(id)`; because that map was last-write-wins,
 * opening a second tab silently stopped the first one receiving anything —
 * it stayed connected and authenticated but was no longer addressable, and
 * push was suppressed for it too. Rooms fix that class of bug outright:
 * Socket.IO maintains membership itself, including removal on disconnect,
 * so there is no map to go stale and no guarded-disconnect dance.
 *
 * Note this is still per-process. Without a Redis adapter a second backend
 * container has its own rooms, so horizontal scale would need one.
 */
export function userRoom(userId: number): string {
  return `user:${userId}`;
}

/**
 * Every live socket for `userId` (one per open tab/device).
 *
 * Only for callers that must inspect socket STATE — currently just push
 * suppression, which reads `client.data.pushClientState`. To merely deliver
 * an event use `server.to(userRoom(id)).emit(...)`, which reaches every tab
 * and is a no-op when the user is offline.
 */
export function socketsForUser(server: Server, userId: number): Socket[] {
  const socketIds = server.sockets?.adapter?.rooms?.get(userRoom(userId));
  if (!socketIds) return [];
  const sockets: Socket[] = [];
  for (const socketId of socketIds) {
    const socket = server.sockets?.sockets?.get(socketId);
    if (socket) sockets.push(socket);
  }
  return sockets;
}

/**
 * Is this user connected on at least one socket?
 *
 * Replaces the old `onlineUsers.has(id)` presence check. Room occupancy is
 * multi-tab correct by construction: closing one of two tabs leaves the room
 * non-empty, whereas the old map could be cleared by whichever socket
 * happened to disconnect last.
 */
export function isUserOnline(server: Server, userId: number): boolean {
  const socketIds = server.sockets?.adapter?.rooms?.get(userRoom(userId));
  return socketIds !== undefined && socketIds.size > 0;
}

/**
 * The user's most recently connected socket, or undefined when offline.
 *
 * The single resolution point for anything that must treat one tab as "the"
 * tab. Delivery of ciphertext and the decision to suppress a push MUST both
 * go through this, or they disagree: address the newest tab while polling
 * every tab for focus and you get the case where the message is delivered to
 * a background tab, the push is suppressed because a DIFFERENT tab is
 * focused, and the user sees neither. Resolving once keeps them coherent by
 * construction — and when the ciphertext carve-out below is lifted, both move
 * to room-wide together.
 */
export function newestSocketForUser(
  server: Server,
  userId: number,
): Socket | undefined {
  const socketIds = server.sockets?.adapter?.rooms?.get(userRoom(userId));
  if (!socketIds || socketIds.size === 0) return undefined;
  // Set preserves insertion order, so the last entry is the newest join.
  let newestId: string | undefined;
  for (const socketId of socketIds) newestId = socketId;
  return newestId ? server.sockets?.sockets?.get(newestId) : undefined;
}

/**
 * Deliver to exactly ONE of the user's tabs — the most recently connected.
 *
 * RESERVED FOR CIPHERTEXT-BEARING EVENTS (`newMessage`, `messageEdited`).
 * Everything else must use `server.to(userRoom(id))` so every tab receives.
 *
 * Why this exists. Signal decryption is NOT idempotent: decrypting a message
 * consumes its message key and advances the ratchet. Both tabs share one
 * IndexedDB session store, and the client's Web Lock serialises them but does
 * not deduplicate them — so fanning one ciphertext to two tabs makes the first
 * decrypt succeed and the second FAIL, landing in the client's decryption
 * failure policy. That path is documented client-side as the most dangerous
 * code in its messaging layer, because a wrong branch there can destroy a
 * working session. Fanning out ciphertext would manufacture that failure on
 * every multi-tab message.
 *
 * Picking the newest socket reproduces exactly the old `onlineUsers` map's
 * last-write-wins behaviour, so this is a no-op relative to today rather than
 * a regression — while every non-ciphertext event still gets the multi-tab fix.
 *
 * TEMPORARY. Remove once the client either (a) checks a shared decrypted-message
 * cache before attempting a live decrypt, race-free, or (b) provably no-ops when
 * a sibling tab already decrypted the ciphertext. Then these two events move to
 * `server.to(userRoom(id))` like everything else — and push suppression must
 * move to room-wide in the SAME change, never separately.
 */
export function emitToNewestTab(
  server: Server,
  userId: number,
  event: string,
  payload: unknown,
): boolean {
  const socket = newestSocketForUser(server, userId);
  if (!socket) return false;
  socket.emit(event, payload);
  return true;
}
