# T4 research — envelope fan-out, device rooms, per-device history reads (spec §5.2/§5.3)

**Date:** 2026-08-20. **Ticket:** T4 (Phase 2). **Purpose:** settle the four open design
points named in `.cursor/session-summaries/2026-08-20-HANDOFF-phase2-T4-start-here.md` §11
BEFORE any code, per the Stage-0 "settle before code" rule.

Five parallel researchers: three read-only codebase scouts (backend send path, client send
path, wire harness) and two librarians against primary sources (Signal-Server/libsignal/
Sesame; Matrix/Signal/WhatsApp multi-device history + receipts). Transcripts:
`history://BackendSendPath`, `history://ClientSendPath`, `history://WireHarnessScout`,
`history://SignalFanoutLibrarian`, `history://HistoryMarkerLibrarian`.

**Process note (new):** `scout` agents have NO write tool — they cannot produce `local://`
files. Ask them to return findings inline and persist them yourself. The two `librarian`
agents did write files.

---

## 1. Codebase ground truth (what T4 converts)

### 1.1 Backend send path
- Gateway `sendMessage` → `chat.gateway.ts:200-207` → `ChatMessageService.handleSendMessage`
  (`chat-message.service.ts:73-247`).
- DTO `SendMessageDto` (`chat/dto/chat.dto.ts:33-105`): `recipientId`, `content`
  (`ValidateIf` no `encryptedContent` and messageType not VOICE/PING/VIDEO, :39-46),
  `encryptedContent?` (≤65536, :49-53), `expiresIn?`, `tempId?`, `sendToken?` (8-64, :64-71),
  `messageType?`, `mediaUrl?`, `mediaDuration?`, `replyToMessageId?`. **No envelope or
  list-version fields.**
- Row written by `MessagesService.create` (`messages.service.ts:47-99`, lone `msgRepo.save`).
  **There is NO `dataSource.transaction`/`manager` seam anywhere in the send path** — T4
  introduces the "one message row + N envelope rows in ONE transaction" boundary from scratch.
- `sendToken` idempotency already landed: pre-check `findBySendToken`
  (`chat-message.service.ts:120-141`, re-ack WITHOUT re-fan) + partial unique index
  `UQ_messages_sender_send_token` (`message.entity.ts:33-36`) + race catch (:150-176).
- `originDeviceId` = `socketDeviceId(client)` (`chat-message.service.ts:51-56`, :158) off the
  JWT claim set at `chat.gateway.ts:135-141`.
- **`message_envelopes` has ZERO write paths today**: grep finds only `app.module.ts:44,:85`,
  `messages.module.ts:4,:13` and the entity itself. Shape as landed
  (`message-envelope.entity.ts`): `id`, `messageId` (+`@ManyToOne onDelete CASCADE`, :50-52),
  `recipientUserId`, `recipientDeviceId`, `ciphertext`, `deliveredAt?`, `readAt?`,
  `createdAt`; UNIQUE `(messageId, recipientUserId, recipientDeviceId)` (:31-35); index
  `(recipientUserId, recipientDeviceId, messageId)` (:36-40); no FK on the recipient pair.
- Named conversion target CONFIRMED: `MessagesService.updateDeliveryStatus`
  (`messages.service.ts:319-344`) ends in a full-entity `save()` at **:343-344**. The law to
  mirror is `markConversationAsReadFromSender` (**:598-609**), already a column-scoped
  `createQueryBuilder().update(Message).set({deliveryStatus})`.
- Rooms: `chat.gateway.ts:143` joins **only** `user:<uid>`. **No `device:<uid>:<did>` room
  exists.** `emitToNewestTab` (`user-room.ts:106-114`, newest socket = last entry of the room
  Set, `:63-79`) carries both ciphertext events: `newMessage`
  (`chat-message.service.ts:195-200`) and `messageEdited` (:670). Its documented removal
  condition sits at `user-room.ts:96-104`. Push suppression
  (`shouldSkipPushForFocusedRecipient`, :680-696) reads `pushClientState` off the SAME socket
  `emitToNewestTab` targets — so the room change and the suppression change are one change.
- `preKeysLow`: counted per-device (`countUnusedPreKeys(userId, targetDeviceId)`) but ROUTED
  per-user (`server.to(userRoom(...)).emit('preKeysLow', {remaining})`,
  `chat-key-exchange.service.ts:531-536`). Rider: route to the device room.
- History serializer: `MessageMapper.toPayload` (`message.mapper.ts:5-77`), echoing
  `encryptedContent` (:38); `handleGetMessages` (`chat-message.service.ts:233-300`) →
  `findByConversation` (`messages.service.ts:157-205`), which takes no deviceId today.
- Refusal house style = request-event → response-event `{success:false, error:code}`
  (`chat-device-list.service.ts:66-71`, :105-110; codes via `DeviceListRejectedError`,
  `device-list.service.ts:53-56`). **The send path is the outlier** — it emits a bare
  `client.emit('error', {message})` (`chat-message.service.ts:83-86`).
- Seams T4 consumes: `DeviceListService.getAuthorization` (`device-list.service.ts:289-291`,
  supplies `dakPub`/`enrollmentSig`/`enrollmentCreatedAt`/`listVersion`/`listSignature`/
  `listCanonical`; wire echo shape at `chat-device-list.service.ts:135-150` with
  `enrollmentCreatedAt` as epoch ms), `DevicesService.{allocateDeviceId,touch,isActive,
  listForUser}` (`devices.service.ts:34-133`).

### 1.2 Client send path
- Single funnel `_encryptAndSend` (`messaging_provider.send.dart:1047-1238`): builds the E2E
  plaintext envelope (:1147-1160), `ensureSession` (:1165), ONE `encrypt` (:1167), 65536
  guard (:1189), lost-ack `savePendingSendRecord(ciphertext, …)` (:1196-1203), then the flat
  emit map (**:1209-1226**): `{recipientId, content:'[encrypted]', encryptedContent, expiresIn,
  tempId, replyToMessageId, [messageType], [mediaUrl], [mediaDuration]}`.
- **`sendToken` does not exist client-side** (grep `sendToken` in `frontend/lib` = 0 hits);
  `tempId` is minted at `send.dart:41-42`.
- **deviceId 1 is hardcoded throughout the crypto layer**: `encryption_service.dart:63`
  `static const int _deviceId = 1`, with `SignalProtocolAddress(userId.toString(), _deviceId)`
  at :961-964 (encrypt), :770 (hasSession), :782 (deleteSession), :817 (buildSession), :1017
  (decrypt), :1148 (fingerprint). `_sessionTails` serialization is keyed by peerId **only**
  (:894-915, cross-context lock name :896). `fetchPreKeyBundle` carries `{userId}` only
  (`encryption_provider.dart:180`, `socket_service.dart:243`).
- Own-sender guards (verbatim, T4 must NOT touch — T5 flips them):
  `decrypt.dart:963-965`, `:975`, `:1294` (`msg.senderId == _currentUserId`), and
  `history.dart:529` (`msg.senderId == _currentUserId && msg.tempId != null`).
- History rows take their ciphertext from the server's `encryptedContent`
  (`message_model.dart:62`, `:158`; decrypt loop `decrypt.dart:691`). Existing placeholder
  vocabulary: `[encrypted]`, `[Decryption failed]`, `[Encryption not initialized]`,
  `[Message no longer stored on this device]` (`messaging_provider.dart:62-64`,
  `encryption_service.dart:1303-1308`, `utils/message_display_text.dart:16`). **No
  per-device "no envelope for me" state exists.**
- `saveDecryptedContent` (`encryption_service.dart:1345-1386`) refuses to let a placeholder
  overwrite real plaintext — any new marker MUST join `placeholderContents` (:1303).
- Device-list machinery: `DeviceAuthorityEngine.verifyPeerDeviceList`
  (`device_list/device_authority_engine.dart:319-386`, I7 chain) is a PURE static verifier
  with **no cache and no persistence**; its only production caller is the T3 link ceremony
  (`link_ceremony_controller.dart:197`, :229). T4 must add the verified-list cache.
- `senderListInfo`: **0 hits** in `frontend/lib`. The E2E plaintext envelope is built by
  `E2eEnvelope.build` (`utils/e2e_envelope.dart:22-49`); `parse` (:51-97) ignores unknown
  keys, so a later additive field costs nothing (the `linkPreview` precedent).

### 1.3 Wire harness
- Registration budget: **exactly 2** (`full_stack_e2e_test.dart:179-180`, alice+bob). Every
  other identity comes from `E2eClient.adoptAccountFrom` (`support/e2e_test_client.dart:262-267`).
  T4 adds ZERO registrations.
- A live `(userId, deviceId≥2)` socket is obtained only via the T3 ceremony
  (`full_stack_e2e_test.dart:1296-1502`): `adoptAccountFrom` → `connectSocket` →
  `openProvisioning` → `provisioningHello` (returns `deviceId`) → DAK-signed `v+1` list →
  `provisionDevice` → `provisioningComplete` (returns the rebind `access_token`, :1446) →
  `disconnect` → swap `accessToken` → `connectSocket` (:1474-1476) → per-device bundle/OTP
  upload. The DAK private key lives ONLY in the main()-scope `engine` (~:176). T3's helpers
  `currentAuth`/`signAddedDevice`/`blobPayloadFor` are group-LOCAL — T4 either nests inside
  that group or hoists a shared linked-device helper to main() scope.
- `_trackedEvents` (`e2e_test_client.dart:~210-260`) is a closed list: **a new server event is
  invisible to `EventLog` until it is added there.**
- `EventLog.next` has no cursor (scans the whole buffer) → `discard()` immediately before the
  triggering emit or a state-transition assert passes vacuously. Deliberate refusals must be
  drained (`takeError`) or the final "no unexpected socket errors" guard (~:1717) fails the run.
- Falsification coverage of T4/T5 targets: **4, 5, 9, 13, 16, 19, 22 — all UNCOVERED.**
  (Covered today: 1, 2, 3, 8, 18, 20, 23, 25.) The existing `getServedMessageIds` test (~:620)
  exercises per-user reconcile single-device only, so falsification 13's marker case is open.
- Backend spec style: `Test.createTestingModule` + `getRepositoryToken(...)` `useValue` repo
  mocks; `repo.query` mocked to the Postgres `[rows, rowCount]` tuple
  (`messages.service.spec.ts:450-453`); SQL asserted by fragment + `mock.invocationCallOrder`;
  gateway tests mock `server.to = jest.fn().mockReturnValue({emit: jest.fn()})` and
  `client.data = {user:{id}}` — the pattern per-device room emits extend.

---

## 2. Prior art (primary sources)

Full files: `local://t4-prior-art-fanout.md`, `local://t4-prior-art-history.md`.

### 2.1 Per-device fan-out and stale rejection (Signal-Server, libsignal, Sesame)
- **The per-device DTO is exactly our planned shape.** `IncomingMessageList.messages :
  List<IncomingMessage>` and `record IncomingMessage(int type, byte destinationDeviceId, int
  destinationRegistrationId, byte[] content)` — one distinct ciphertext per device, no shared
  ciphertext (`entities/IncomingMessageList.java:26-37`, `entities/IncomingMessage.java:33-40`).
- **Duplicate device targets are rejected**, not last-wins: `isNotDuplicateRecipients()`
  (`IncomingMessageList.java:55-68`). Borrow this.
- **Validate-then-insert is prior art**: `validateIndividualMessageBundle`
  (`push/MessageSender.java:313-359`) throws `MismatchedDevicesException` at :353-355 BEFORE
  `messagesManager.insert`; the javadoc (~:280-289) states the validator exists precisely so a
  caller "cannot reverse that action if message sending fails". Zero rows on reject.
- Mismatch is set algebra over the account's current devices plus per-device registration ids
  (`MessageSender.java:391-423`).
- **Signal's reject payload is IDs ONLY** — `MismatchedDevicesResponse{missingDevices,
  extraDevices}` (409) and `StaleDevicesResponse{staleDevices}` (410), both `Set<Byte>`
  (`entities/*Response.java:19-28`, mapped at `controllers/MessageController.java:413-431`).
  The client must then make a SECOND `/keys` round trip. **Our planned payload (the whole
  signed list + signature + enrollment + version) is structurally stronger and repairs in ONE
  round trip** — and it is what Sesame's abstract server is explicitly allowed to do: §3.3
  says the server informs the sender of old/new DeviceIDs "AND the identity public keys
  corresponding to any new DeviceIDs".
- **A bounded retry loop is normative**, count unspecified: Sesame §3.3/§4.1 — devices "should
  impose some limit on the number of times they're willing to repeat the message sending
  loop". Our cap 3 then surfaced failure is consistent.
- **Decrypt is NOT idempotent — never broadcast one ciphertext.** Sesame §2.1 (a session
  "might contain different data after … decrypting", keys deleted for forward secrecy) and
  §3.4 (exactly one session decrypts; on failure all state changes are discarded);
  libsignal removes the message key on use (`rust/protocol/src/state/session.rs:455`) and
  bounds retained keys (:480-482). Prior art's per-device `content` (F1) is the direct
  refutation of any blanket broadcast.
- **Deliberate divergence:** Signal and Matrix TRUST the server's device set — neither does a
  cryptographic membership cross-check at send time. Ours is DAK-signed and client-verified,
  which is exactly why the reject payload MUST carry `listSignature` + `enrollment`.

### 2.2 History predating a link, receipts, disappearing (Matrix, Signal, WhatsApp)
- **Matrix is the strongest prior art for an explicit marker, at two levels.** (a) Client
  cause enum `matrix-sdk-crypto::UtdCause` has a dedicated `SentBeforeWeJoined` variant —
  renamed from `Membership` in 2024-10 — kept distinct from generic `Unknown`. (b) Wire level:
  MSC2399's `m.room_key.withheld` carries a machine-readable `code`
  (`m.blacklisted`/`m.unverified`/`m.unauthorised`/`m.unavailable`/`m.no_olm`). MSC2399's
  motivation is verbatim ours: without it "devices that have not received keys do not know why
  … and so cannot inform the user as to whether it is expected that the message cannot be
  decrypted" (matrix-ios-sdk#1354).
  → **`envelopeStatus` as an extensible STRING enum is the industry-consistent shape.**
- **Signal and WhatsApp have no marker because they are per-device MAILBOX models**, not
  server-row models: a newly linked Signal device sees "only new messages show up"
  (signal.org/blog/a-synchronized-start-for-linked-devices/), and pre-link history arrives
  only through an OPTIONAL device-to-device encrypted archive (Signal 2025; WhatsApp companion
  transfer, engineering.fb.com 2021-07-14) — which is precisely our Phase-4 non-goal. Fireplace
  keeps a reconcile-visible row for every message (I8), so Fireplace uniquely NEEDS the marker.
- **Receipts:** Signal separates peer-originated receipts from own-device sync; a read receipt
  sent to a peer does not sync to your own devices without a `readMessages` sync
  (signal-cli#1570). No system has a sender's own device generating a receipt to the sender.
  This backs §4's recipient-envelopes-only projection. **Caveat: an explicit published "own
  devices never count" sentence is `[NOT FOUND]`** — the conclusion is `[INFERENCE]` from the
  receipt-vs-sync split. Do not overclaim external endorsement.
- **Disappearing:** Signal's timers are per-device and client-local; the service does not know
  a message is disappearing, and an offline device applies deletion on reconnect
  (support.signal.org/hc/en-us/articles/5532268300186). Our §5.6 "same behavior as Signal" is
  true for the user-visible OUTCOME but the MECHANISM diverges (one server deadline vs
  per-device timers that can OVER-retain). Keep doc/UI phrasing outcome-scoped.
- `[NOT FOUND]`: WhatsApp's behavior for messages older than the transferred window.

---

## 3. Settled design points (→ spec §12 amendment 2026-08-20, items (v)–(viii))

- **DP1 — DTO + legacy ingest.** Grow `SendMessageDto` additively with
  `envelopes: [{userId, deviceId, ciphertext}]`, `senderListVersion?`, `recipientListVersion?`.
  A legacy single-`encryptedContent` send is NORMALIZED AT INGEST into a one-element envelope
  list `[{userId: recipientId, deviceId: 1, ciphertext: encryptedContent}]`, so exactly ONE
  downstream write path exists (Signal's normalized `messagesByDeviceId`, §2.1). New-model rows
  never write `encryptedContent`. Duplicate `(userId, deviceId)` pairs are rejected, mirroring
  `isNotDuplicateRecipients`.
- **DP2 — `deviceListStale`.** A response-event refusal in house style, carrying an ARRAY of
  the stale parties (1 or 2 entries) plus `tempId` for correlation, so one round trip repairs
  both lists. Checked BEFORE any persistence (zero envelopes written).
- **DP3 — `senderListInfo` DEFERS to T5.** The server is blind to it (E2E plaintext); its
  falsifications (16, 22) are recipient-side and both uncovered; the guards it interacts with
  are the ones T5 flips. Landing only the field in T4 would be dead weight.
- **DP4 — `envelopeStatus`.** Additive string field on the message payload; the served
  ciphertext continues to ride the EXISTING `encryptedContent` wire field (no new ciphertext
  field, so older clients are untouched). Two values: `none_for_device` (row predates this
  device's link) and `own_origin` (this device sent it; there is no envelope for the origin
  device by design) — a second value is required so the origin device does not render "sent
  before this device was linked" over its own outbound rows. Marker rows carry no ciphertext,
  never overwrite locally cached plaintext, and are never a destruction trigger (I8).

Binding riders carried into the writer briefs: `preKeysLow` routed to the device room;
`updateDeliveryStatus` → column-scoped UPDATE, projecting over RECIPIENT envelopes only;
envelope stamps never entering expiry/read-TTL; the landmine-2 red test (a device-2 bundle
upload under the shared IK must not trip `[identity-churn]`); and confirming that recipient-user
deletion cannot orphan envelopes (they cascade only via the `messageId` FK).
