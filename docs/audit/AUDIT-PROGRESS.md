# Fireplace — Full Codebase Security & Quality Audit · Progress Tracker

**Branch:** `audit/full-review` (off `08bbe23`, branch `fix/android-pwa-push-reliability`)
**Auditor:** Claude (Opus 4.8) · senior appsec + full-stack
**Started:** 2026-06-14
**Mode:** Report-only (no app-code changes this pass). Depth: risk-weighted (deep on
security/E2E/auth/push/backend/data-lifecycle; complete-but-lighter on UI). Scope: app code
**+ infra (docker/nginx/deploy/CI) + dependencies**. Order: E2E + auth + push first.

Deliverables (all under `docs/audit/`):
- `AUDIT-PROGRESS.md` (this file — the tracker)
- `MODULE-MAP.md` (module map + trust-boundary / data-flow overview)
- `FINDINGS.md` (prioritized findings report + action list + strengths)

Legend: ⬜ pending · 🔶 in-progress · ✅ done

---

## Inventory (counts)
- Backend source: **100** `.ts` (≈7.4k LOC) + 41 `.spec.ts`
- Frontend lib: **177** `.dart` (≈26.9k LOC) + 72 test files
- Service worker: `frontend/web/web-push-sw.js` (+ manifest, index.html)
- Infra: docker-compose(.yml/.web.yml), backend `Dockerfile(.dev)`, frontend `Dockerfile`,
  `frontend/nginx.conf`, `deploy.sh`, `.env`, `scripts/`
- CI: `.github/workflows/ci.yml`
- Deps: backend `package.json`, frontend `pubspec.yaml`/`pubspec.lock`

---

## Audit chunks

### Phase 0 — Inventory & map
- ✅ P0.1 Enumerate repo, counts, top-level tree
- ✅ P0.2 MODULE-MAP.md (module map + trust boundaries + data flow)

### Backend (priority block: auth + E2E key exchange + push first)
- ✅ B1  Bootstrap & config — main/app.module/env.validation/version/health. CORS dev-bypass OK; `synchronize` on raw `process.env.NODE_ENV` (M-03). 0 hi.
- ✅ B2  Auth — refresh rotation race + 365d TTL (M-01); DEV_JWT_SECRET fallback (L-01); login enum/timing (L-02). Strong: bcrypt, hashed refresh, pwChangedAt invalidation (REST).
- ✅ B3  Users — endpoints JWT-guarded; `removeFcmToken` unscoped (M-02); global-username dead code (L-03); deleteAccount skips secret_notes (L-04). bcrypt 72B (I-01).
- ✅ B4  E2E key exchange (backend) — uploads self-scoped (good); fetch no friendship gate + OTP depletion (L-05); requestSessionRebuild no conv check (L-06); used-OTP rows never pruned (info).
- ✅ B5  Gateway + WS guards + DTO validator — **WS handshake skips `passwordChangedAt` check (M-05)**; several state-changing handlers unthrottled (L-08); WS DTOs not whitelisted (info).
- ✅ B6  Chat services I — **getMessages IDOR (H-01)**; deep-pagination memory (M-06); delivered/read/clear/delete all membership-checked (good). messageType `@IsString` not `@IsIn` (L-09).
- ✅ B7  Chat services II — friend-request/block/reaction/search all correctly authz'd to caller. Search exact-handle only. No findings.
- ✅ B8  Link preview — **SSRF filter bypass (alt IP enc) + no resolve-pin (M-04)**; reachable via `POST /messages/link-preview` + plaintext message. 800KB/5s caps good.
- ✅ B9  Messages — entity/mapper/cleanup/expiry. Expiry SQL interpolates a constant (safe). Mapper reply-preview uses placeholders for E2E (good).
- ✅ B10 Conversations — findOrCreate/pin/delete all membership-checked. Clean.
- ✅ B11 Friends + blocked — acceptRequest/rejectRequest enforce receiver==caller; block/unblock caller-scoped. Clean.
- ✅ B12 Media — **path traversal → arbitrary file delete (H-02)**; `/media/msgs` authz-by-UUID only (L-07); avatar serving traversal-safe; upload size/mime/magic OK.
- ✅ B13 Secret notes — E2E-correct (fragment key, atomic read-once); landing-page `${token}` unescaped but unreachable (info, defense-in-depth).
- ✅ B14 Push (backend) — payloads **metadata-only**, web-push body VAPID-encrypted (strong); senderName→FCM/Google metadata leak (info). Coalescing/dup-suppress sound.
- ✅ B15 Health + mappers — no-auth health/version intended; UserMapper no sensitive fields. Clean.

### Frontend (priority: E2E + auth + push)
- ⬜ F1  Bootstrap — `main.dart`, `config/*`, `firebase_*`, `constants/*`
- ⬜ F2  Models — `models/*`
- ⬜ F3  Auth + REST — `providers/auth_provider.dart`, `services/api_service.dart`, `services/session_refresh_exception.dart`
- ⬜ F4  Connection/Socket — `providers/connection_provider.dart`, `services/socket_service.dart`, `providers/chat_reconnect_manager.dart`
- ⬜ F5  Conversations — `providers/conversations_provider.dart`, `providers/conversation_helpers.dart`
- ⬜ F6  Messaging provider (core + 5 part-files) — `providers/messaging_provider.dart`, `providers/messaging/*`
- ⬜ F7  E2E crypto — `providers/encryption_provider.dart`, `services/encryption_service.dart`, `services/encryption/signal_stores.dart`, `utils/e2e_envelope.dart`, `utils/decryption_failure_policy.dart`, `utils/e2e_diag_log.dart`
- ⬜ F8  Media crypto — `services/media_crypto_service.dart`, `services/encrypted_media_upload_service.dart`, `utils/audio_*`, `utils/gif_blob_url*`, `services/gif_service.dart`
- ⬜ F9  Friends + Settings providers — `providers/friends_provider.dart`, `providers/settings_provider.dart`
- ⬜ F10 Push/badge (frontend) — `services/push_service.dart`, `web_push_bridge*`, `push_sw_channel*`, `android_fcm_local_notifications.dart`, `fcm_background_stub.dart`, `push_android_stub.dart`, `badging_bridge*`, `unread_badge_sync.dart`, `notification_cleaner*`, `pwa_app_badge_clear.dart`, `utils/app_badge_math.dart`, `utils/notify_conv_param*`, `utils/pending_deep_link*`
- ⬜ F11 Screens — `screens/*`
- ⬜ F12 Input widgets — `widgets/input/*`, `widgets/chat_input_bar.dart`
- ⬜ F13 Message widgets — `widgets/message/*`, `widgets/chat_message_bubble.dart`, `widgets/voice_message_bubble.dart`, `widgets/audio/*`
- ⬜ F14 Other widgets — `widgets/*` (dialogs, tiles, overlays, anti-quantum note, etc.)
- ⬜ F15 Web platform shims — `utils/web_*`, `utils/*_stub/_web` pairs, `utils/document_visibility*`, `utils/soft_keyboard*`, `utils/storage_persist*`, `utils/secure_context*`, `services/web_orientation_lock*`
- ⬜ F16 Misc utils — `utils/message_expiry.dart`, `reply_preview_helper.dart`, `scroll_to_message_helper.dart`, `pinned_banner_visibility.dart`, `portrait_lock_policy.dart`, `audio_mime.dart`, `page_load_nonce.dart`, `mic_permission_state*`, `services/link_preview_service.dart`, `services/voice_audio_coordinator.dart`, `services/incoming_message_sound_service.dart`, `services/portrait_lock_service.dart`
- ⬜ F17 Theme + l10n — `theme/*`, `l10n/*`

### Service worker / web shell
- ⬜ SW1 `frontend/web/web-push-sw.js`, `frontend/web/manifest.json`, `frontend/web/index.html`

### Infra & supply chain
- ⬜ I1 Docker/compose/nginx/deploy — `docker-compose*.yml`, `backend/Dockerfile*`, `frontend/Dockerfile`, `frontend/nginx.conf`, `deploy.sh`, `.env`, `scripts/`
- ⬜ CI1 CI — `.github/workflows/ci.yml`
- ⬜ D1 Dependencies — backend `package.json` + `package-lock.json`, frontend `pubspec.yaml`/`pubspec.lock`

### Cross-cutting passes (Phase 2)
- ⬜ X1 End-to-end E2E flow (keygen→prekey→session→encrypt→transport→decrypt→failure/rebuild)
- ⬜ X2 AuthN/AuthZ matrix across every REST endpoint + WS event
- ⬜ X3 Untrusted-input flow (SSRF / injection / path traversal / regex DoS)
- ⬜ X4 Concurrency/races (optimistic send, reconnect, decrypt order, badge/push)
- ⬜ X5 Data lifecycle (account delete cascade, media cleanup, expiry, orphans)

---

## Chunk log (one line per chunk when done: status + finding count + summary)

_(updated as chunks complete)_

---

## Coverage statement
_(filled at the end — must assert 100% of chunks audited or list deferrals + reasons)_
