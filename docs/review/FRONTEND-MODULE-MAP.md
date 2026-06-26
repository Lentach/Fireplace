# Fireplace Frontend — Module Map & Critical-Path Overview

Provenance: inventory is `find`-verified (184 lib Dart files, 79 tests). The bootstrap/auth-gate
path below is source-verified (`main.dart`). Remaining per-module behavior is summarized from
`frontend/CLAUDE.md` and confirmed file-by-file in the Phase-1 chunk reviews.

## Layered architecture

```mermaid
graph TD
  main[main.dart bootstrap] --> app[FireplaceApp MultiProvider]
  app --> gate[AuthGate]
  gate -->|logged out| auth[AuthScreen]
  gate -->|logged in| shell[MainShell IndexedStack]
  shell --> conv[ConversationsScreen]
  shell --> contacts[ContactsScreen]
  shell --> settings[SettingsScreen]
  conv --> chat[ChatDetailScreen]

  subgraph Providers (ChangeNotifier x7)
    AuthP[AuthProvider]
    ConnP[ConnectionProvider socket lifecycle]
    ConvP[ConversationsProvider]
    MsgP[MessagingProvider + 5 part-files]
    FriP[FriendsProvider]
    EncP[EncryptionProvider Signal]
    SetP[SettingsProvider]
  end

  subgraph Services
    Sock[SocketService]
    Api[ApiService REST]
    Enc[EncryptionService Signal]
    Stores[signal_stores 4 stores]
    MCrypto[MediaCryptoService AES-256-GCM isolate]
    MUpload[EncryptedMediaUploadService]
    Push[PushService + web_push_bridge]
    Link[LinkPreviewService]
  end

  ConnP --> Sock
  ConnP -->|routes events| ConvP & MsgP & FriP & EncP
  MsgP --> Enc --> Stores
  MsgP --> MUpload --> MCrypto & Api
  AuthP --> Api
  Push -->|web| SW[web/web-push-sw.js]
```

## Critical paths (the ones the go/no-go hinges on)

1. **App bootstrap + auth gate** — `main()` → `PortraitLockService.initialize()` → file-picker init →
   (native only) `Firebase.initializeApp` + `onBackgroundMessage` → consume IndexedDB/URL deep-link →
   `runApp(FireplaceApp)` → `MultiProvider` (7) → `MaterialApp(builder: PortraitLockShell)` →
   `AuthGate` (watch `AuthProvider`; on `true→false` logout transition postFrame `conn.disconnect`;
   route `MainShell` / `AuthScreen`). [source-verified `main.dart:29-138`]
   — chunk **C1**.

2. **Socket / connection lifecycle** — `ConnectionProvider` owns `SocketService`, registers event
   listeners, fans out to sub-providers; reconnect storm guard, resume liveness probe (zombie socket),
   force-new on reconnect. — chunk **C2**.

3. **E2E key / session handling** — `EncryptionService` (libsignal Double Ratchet) + 4 `signal_stores`
   over `DualStorage` (mobile: secure+SP; web: SP/localStorage only); `EncryptionProvider` decrypted-
   content cache (cap 2000); OTP replenish; session inventory/durability probes. — chunk **C3**.

4. **Message send / receive / decrypt** — `MessagingProvider` core + parts: optimistic send (temp id =
   -timestamp → encrypt → `sendMessage` → `messageSent` reconcile), history merge-by-id, live decrypt
   serialized per sender, terminal `[Decryption failed]`, edit-as-new-ciphertext. — chunk **C4**.

5. **Media encrypt / upload / playback** — `EncryptedMediaUploadService` wraps `MediaCryptoService`
   (AES-256-GCM in isolate) + `ApiService.uploadEncryptedMedia`; one-shot media keys; voice playback
   via `VoicePlayer` (native just_audio / web Web-Audio); blob MIME sniff. — chunk **C6**.

6. **Push / notifications + SW** — `PushService` + `WebPushBridge` (VAPID, scope `/web-push-scope/`);
   `web-push-sw.js` (push handler, tray one-card-per-conv, badge single-writer, deep-link carriers);
   native FCM data-only → `flutter_local_notifications`; `UnreadBadgeSync`. — chunks **C7** (app) + **C8** (SW).

7. **Navigation / deep-link** — provider→screen poll pattern (`consumePendingOpen` etc.); 3 push
   deep-link carriers (alive postMessage / cold-start URL param / iOS IndexedDB record). — C1/C7/C8/C10.

## Area → chunk index
See `FRONTEND-REVIEW-PROGRESS.md` for the 15-chunk decomposition and per-chunk file lists.
