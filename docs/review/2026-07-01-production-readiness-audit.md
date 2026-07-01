# Fireplace production-readiness audit — 2026-07-01

**Branch audited:** `docs/claude-rebuild`  
**HEAD audited:** `8fb8624 chore: prune stale cleanup leftovers`  
**Base comparison:** `origin/master...HEAD` = `0 left / 4 right` after adding this audit report  
**Deploy status:** not deployed by this audit. Public production endpoints were read-only checked only.

## Verdict: NOT READY

The branch is cleaner and the local verification baseline is green, but that is not production readiness. Release sign-off is blocked by live production freshness/metadata drift and missing live end-to-end smoke evidence for the deploy-sensitive areas.

This audit did **not** find a new source-level blocker that should be fixed by random cleanup. The code paths inspected mostly match the current docs. The release problem is operational proof: production is not proven to be running the audited code, and the backend `/version` metadata is still not truthful.

## Exact blockers

1. **Production backend freshness is not proven and `/version` is still stale/untruthful.**
   - Public `https://fireplace.ignorelist.com/version` returned `{ "version": "0.0.2", "gitCommit": "dev", "buildTime": "" }` during this audit.
   - Current audited HEAD is `8fb8624`; `deploy-backend.sh` is supposed to inject `APP_VERSION`, `GIT_COMMIT`, and `BUILD_TIME` from the VM deploy flow.
   - Evidence: `deploy-backend.sh` exports `GIT_COMMIT`, `BUILD_TIME`, and `APP_VERSION`, then verifies `/version` and `/health`; `docker-compose.prod.yml` passes those env vars to the backend.
   - Release impact: any claim that production runs this branch would be fake. VM inspection/deploy verification is required before release sign-off.

2. **Production frontend is not proven to be the audited code.**
   - Public `https://fireplace.ignorelist.com/version.json` returned `0.0.76`; audited branch and `origin/master` both show `frontend/pubspec.yaml` version `0.0.75`.
   - The repo explicitly warns semver is not enough because Flutter/PWA caching can serve stale bundles; Settings footer `gitCommit` or a fresh `deploy-web.ps1` verification is required.
   - Release impact: public frontend freshness is ambiguous. The branch cannot be certified live without the served commit evidence.

3. **No live E2E/push/media smoke test was run.**
   - Local tests cover many contracts, but they do not prove real PWA service worker delivery, iOS standalone push behavior, VAPID match, real Signal key persistence across PWA lifecycle, or VM media deletion on the live volume.
   - This audit intentionally did not deploy and did not clear site data/uninstall any PWA because that would destroy local Signal keys.

4. **Branch still needs PR/review and explicit merge approval.**
   - `docs/claude-rebuild` is `4` commits ahead of `origin/master`, `0` behind after this audit report commit.
   - Repo rule: bigger/multi-file release-readiness work stays on a feature branch/PR and must not merge to `master` without explicit user approval.

## Non-blocking risks

- **No real TypeORM migrations exist.** Entities are source of truth and prod has `synchronize` off. Current audited branch does not add entity columns, but any future release with DB fields needs manual SQL and verification. Raw SQL must quote camelCase PostgreSQL identifiers.
- **Some WebSocket actions are intentionally not throttled.** Docs now say not all read/friend/unblock events are throttled. This is not a new blocker, but it should stay explicit.
- **Diagnostics remain in the app.** `E2eDiagLog`, storage durability probes, mic logs, and composer diagnostics are intentionally retained because the underlying field issues are not closed. They are noisy, but deleting them now would be the kind of neat-looking vandalism that breaks incident response.
- **Web Push can only be certified with live keys.** Code requires frontend `WEB_PUSH_VAPID_PUBLIC_KEY` to match backend VAPID env. Local tests cannot prove the production key pair matches the deployed bundle.
- **Backend runs as root inside the production image.** `backend/Dockerfile` has no `USER` directive. Existing compose binds only localhost and stores media in a Docker volume, so this is a hardening risk, not a release blocker found in the requested cleanup scope.
- **Hardcoded English remains in the E2E diagnostic panel.** The user-facing app should prefer ARB, but this panel is diagnostic/protected by current docs. Not changed.

## Suspicious but not removed

- `frontend/lib/screens/privacy_safety_screen.dart` diagnostic strings: kept because E2E diagnostics are explicitly protected until the storage/lifecycle field issue is closed.
- `frontend/lib/widgets/input/composer_diagnostics_overlay.dart`: kept because composer diagnostics are explicitly protected.
- `E2eDiagLog` calls in connection, messaging, encryption, and recording paths: kept because they are tied to unresolved production field issues.
- Legacy Cloudinary URL acceptance in `MEDIA_URL_REGEX`: kept for backward compatibility with old stored media URLs.
- Historical docs under `docs/plans/`, `docs/futures/`, and old `.cursor/session-summaries/`: not rewritten wholesale; they are archived history, not current instructions.
- `deploy.sh`: kept as legacy/all-in-one script because root/tier docs explicitly tell operators not to use it for production; deleting it was not proven safe in this audit.

## Branch/release state

- `git status --short --branch`: `docs/claude-rebuild...origin/docs/claude-rebuild`, clean tree before report creation.
- `git rev-list --left-right --count origin/master...HEAD`: `0 4` after this audit report commit.
- Source HEAD audited before report creation: `8fb8624`.
- `git show --stat --summary 8fb8624` showed the previous cleanup commit deleted stale root manual JS scripts/manifests, removed obsolete frontend shim files, removed unused backend refresh-token cleanup, corrected docs, and hardened the test-count verifier.
- Decision: continuing on `docs/claude-rebuild` is appropriate; it needs PR/review before merge. No merge was attempted.

## Frontend readiness

### What was checked

- Analyzer: `flutter analyze --no-fatal-infos`.
- Full test suite: `flutter test`.
- Import fallout from deleted widget shims: imports now point to real widget locations under `widgets/input/` and `widgets/message/`; no imports reference the deleted root shim files.
- PWA/push scope paths:
  - `frontend/web/web-push-sw.js` owns notification click, badge, close/sweep, pending deep-link IndexedDB, and `pushsubscriptionchange` message fan-out.
  - `frontend/lib/services/web_push_bridge_web.dart` registers `/web-push-sw.js` with scope `/web-push-scope/`, subscribes with `applicationServerKey`, and calls `navigator.serviceWorker.startMessages()` for click messages.
  - `frontend/lib/services/push_sw_channel_web.dart` targets `getRegistration('/web-push-scope/')`, not `serviceWorker.ready`/`.controller`.
- Platform guards:
  - Conditional imports use `dart.library.html` / `dart.library.io` and shared stubs.
  - `file_utils` native cleanup is guarded by `!kIsWeb`.
- E2E media key path:
  - `EncryptedMediaUploadService.encryptAndUpload()` calls `onEncrypted(key, iv)` before upload awaits.
  - `MessagingProvider` preserves `mediaKey`/`mediaIv` in `_pendingSendContent` and on optimistic messages for image/voice/GIF/file send and retry paths.
- Context usage:
  - Analyzer found no issues.
  - Existing explicit `use_build_context_synchronously` ignores are limited and known; the diagnostic-panel ignore follows `if (!mounted) return`.

### Frontend result

No confirmed frontend cleanup blocker was found. Full local Flutter tests passed, but live PWA cache/push/device behavior remains unproven until production deploy verification and device smoke tests.

## Backend readiness

### What was checked

- Build: `npm run build`.
- Full Jest: `npm test`.
- Test-count guard: `node scripts/verify-claude-backend-test-counts.mjs`.
- Production env assumptions:
  - `backend/src/app.module.ts` sets TypeORM `synchronize: process.env.NODE_ENV !== 'production'`.
  - `backend/src/main.ts` restricts production CORS to `ALLOWED_ORIGINS`, applies `helmet()`, and uses `ValidationPipe({ whitelist: true })`.
  - `docker-compose.prod.yml` sets `NODE_ENV: production`, bind-publishes backend/db only on `127.0.0.1`, defines healthcheck, and passes required env vars.
- Socket.IO auth/events/rooms:
  - Frontend `SocketService` sends JWT via Socket.IO `auth.token`, not query string.
  - `ChatGateway` reads `client.handshake.auth.token`, verifies JWT, rejects stale tokens after password change, joins `user:<id>`, and emits `socketReady`.
  - Stale socket disconnect is guarded by socket id before deleting `onlineUsers[userId]`.
  - Room/targeted emits use `server.to(socketId)`/user rooms where relevant.
- DTO/media validation:
  - `SendMessageDto` validates `mediaUrl` against legacy Cloudinary or exact self-hosted `MEDIA_BASE_URL/media/(avatars|msgs)/filename.ext`.
  - `validateDto()` is used in gateway services instead of raw object trust.
- Production logging sensitivity:
  - Logs inspected did not show plaintext message bodies, tokens, private keys, or raw Signal ciphertext logging in the inspected hot paths.
  - Some logs include usernames/user IDs/socket IDs and push subscription endpoints on delivery errors; that is operational metadata, not E2E plaintext.

### Backend result

No source-level backend release blocker was confirmed in this branch. The blocking backend issue is live deploy/freshness: public `/version` still reports stale fallback metadata.

## E2E encryption/key-storage readiness

- Shared docs and code agree on encrypted message shape: server stores `content: '[encrypted]'` plus `encryptedContent`; frontend builds an E2E envelope containing `{ content, messageType, mediaUrl, mediaDuration, mediaKey, mediaIv, linkPreview }` before Signal encryption.
- Ciphertext type convention remains documented as `3` = PreKey, `2` = Signal/whisper.
- Web Signal keys use `SharedPreferencesAsync`/localStorage with `sig_` prefix; mobile uses `flutter_secure_storage`.
- Keys persist through logout; account deletion/site-data clearing removes keys with no recovery.
- Inbound decrypt failures and storage durability probes remain intentionally instrumented.

Result: local source/contracts are coherent. Live cross-reload/device durability is not certified by this audit.

## Push/PWA readiness

- VAPID contract exists in both tiers:
  - Frontend `PushService` uses `WEB_PUSH_VAPID_PUBLIC_KEY` and Web Push registration/subscription.
  - Backend `PushNotificationsService` initializes `web-push` with `WEB_PUSH_VAPID_PUBLIC_KEY`, `WEB_PUSH_VAPID_PRIVATE_KEY`, and `WEB_PUSH_VAPID_SUBJECT`.
  - `deploy-web.ps1` passes the public VAPID key into the Flutter build; `docker-compose.prod.yml` requires backend VAPID keys.
- Web Push payload is metadata-only: `conversationId`, unread counts, unread conversation IDs, and sender display name. No plaintext message body or media keys are sent.
- Push SW click/deep-link behavior matches the documented iOS workaround: postMessage to existing clients, `clients.openWindow('/?notify_conv=...')`, and IndexedDB pending-deep-link fallback.

Result: source is coherent; production push delivery is not certified without live VAPID match and device/browser evidence.

## Media/storage/cleanup readiness

- Self-hosted media URLs are constrained by DTO regex and deletion goes through `LocalStorageService.deleteFile()` with resolved-path containment.
- Legacy Cloudinary URLs are accepted by DTOs but skipped by local deletion, which is intentional for backward compatibility.
- Destructive paths inspected:
  - Delete conversation: `ChatConversationService.handleDeleteConversationOnly()` collects media URLs, deletes self-hosted files, then deletes messages/conversation.
  - Clear history: `ChatMessageService.handleClearChatHistory()` deletes media files before message rows.
  - Delete for everyone: `ChatMessageService.handleDeleteMessage()` deletes the media file before hard-delete, then clears pin if needed.
  - Unfriend: `ChatFriendRequestService.handleUnfriend()` deletes conversation media before deleting the conversation.
  - Block: `BlockedService.block()` deletes conversation media before deleting the conversation.
  - Account delete: `UsersService.deleteAccount()` deletes avatar, push tokens/subscriptions, key bundles, and all conversation media before DB row removal.
- Cron cleanup protects in-flight uploads with `MEDIA_CLEANUP_GRACE_MS` and logs scanned/deleted/orphan/expired/graceSkipped counts.

Result: source-level media cleanup is release-credible; live volume cleanup was not exercised.

## Deploy/production VM readiness

- No VM SSH inspection was performed.
- No deploy was performed.
- Public endpoint checks:
  - `https://fireplace.ignorelist.com/health` returned `{ "status": "ok", "db": "ok" }`.
  - `https://fireplace.ignorelist.com/version` returned stale fallback metadata: version `0.0.2`, gitCommit `dev`, empty buildTime.
  - `https://fireplace.ignorelist.com/version.json` returned frontend version `0.0.76`.
- Required next deploy proof before release:
  1. On VM: `cd ~/fireplace && ./deploy-backend.sh`, then verify local Docker health, `/version`, `/health`, and public `/version`.
  2. From PC: `.\deploy-web.ps1` from repo root, then verify `/version.json` and Settings footer commit.
  3. Fully close + reopen PWA; do not uninstall or clear site data.

## Scripts/config/docs hygiene

- Root stale manual JS scripts and root npm manifest/lockfile were already deleted by `8fb8624`; current grep found only archived references in historical docs/session summaries.
- CI references current paths: backend `npm test`, test-count verifier from repo root, frontend `flutter analyze --no-fatal-infos`, and `flutter test`.
- Deploy docs match source: production web build is PC-side `deploy-web.ps1`; backend is VM-side `deploy-backend.sh`; `deploy.sh` is legacy.
- No new code cleanup was applied in this audit; the visible report is the only tracked deliverable created.

## External references used

- Flutter web FAQ — caching/service-worker caveats and stale asset warning: https://docs.flutter.dev/platform-integration/web/faq
- Flutter web deployment — `flutter build web` output and release validation: https://docs.flutter.dev/deployment/web
- Dart analyzer `unused_import`: https://dart.dev/tools/diagnostics/unused_import
- Dart analyzer `unnecessary_import`: https://dart.dev/tools/diagnostics/unnecessary_import
- Dart linter `use_build_context_synchronously`: https://dart.dev/tools/linter-rules/use_build_context_synchronously
- Dart conditional imports/exports: https://dart.dev/tools/pub/create-packages#conditionally-importing-and-exporting-library-files
- NestJS lifecycle/providers/testing/gateway/validation/logger docs via official docs source: https://github.com/nestjs/docs.nestjs.com
- TypeORM DataSource options and `synchronize` production warning: https://typeorm.io/docs/data-source/data-source-options/
- TypeORM migrations setup and CLI schema sync docs: https://typeorm.io/docs/migrations/setup/ and https://typeorm.io/docs/advanced-topics/using-cli/
- PostgreSQL quoted identifiers: https://www.postgresql.org/docs/current/sql-syntax-lexical.html
- Socket.IO auth/listener/rooms/disconnection docs: https://socket.io/docs/v4/client-options/#auth, https://socket.io/docs/v4/client-api/#socketoffeventname-listener, https://socket.io/docs/v4/rooms/, https://socket.io/docs/v4/tutorial/handling-disconnections
- Docker Compose env/interpolation/services docs: https://docs.docker.com/compose/how-tos/environment-variables/, https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/, https://docs.docker.com/reference/compose-file/services/
- Docker volumes persistence/prune behavior: https://docs.docker.com/engine/storage/volumes/
- MDN Push API: https://developer.mozilla.org/en-US/docs/Web/API/Push_API
- MDN Service Worker API: https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API
- MDN ServiceWorkerRegistration: https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration
- MDN `notificationclick`: https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerGlobalScope/notificationclick_event
- Apple web push for web apps and browsers: https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers
- `web-push` VAPID README: https://github.com/web-push-libs/web-push
- Firebase Cloud Messaging Flutter receive/background handler docs: https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
- Firebase FCM message types: https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type

## Verification commands and results

- `cd frontend && flutter analyze --no-fatal-infos` — passed: `No issues found!`.
- `cd frontend && flutter test` — passed: `421` tests, `All tests passed!`.
- `cd backend && npm run build` — passed: `nest build` exited 0.
- `cd backend && npm test` — passed: `41` suites, `328` tests.
- `node scripts/verify-claude-backend-test-counts.mjs` — passed: `OK: CLAUDE.md matches Jest (328 tests, 41 suites)`.
- Public read-only checks:
  - `/health` — `status: ok`, `db: ok`.
  - `/version` — stale/untruthful backend metadata (`0.0.2`, `dev`, empty build time).
  - `/version.json` — frontend semver `0.0.76`.

## Files changed by this audit

- Added `docs/review/2026-07-01-production-readiness-audit.md`.
- Updated session summary files separately.
- No application code changed. No version bump. `graphify update .` not required for docs-only changes.
- Code-reviewer was requested before final; the background reviewer failed with `usage_limit_reached`, so no independent review findings were returned.

## Required next action before production release

Do the boring deploy proof instead of vibe-checking it:

1. Open/merge the release-readiness branch only after review and explicit user approval.
2. Deploy backend on the VM with `./deploy-backend.sh`; verify public `/version` reports the actual merged commit and semver.
3. Deploy frontend from the PC with `.\deploy-web.ps1`; verify `/version.json` and Settings footer commit.
4. Run live smoke tests on a real PWA/device pair without clearing site data: login/session refresh, E2E text send, encrypted media send/open, push notification receive/click, conversation delete/clear/delete-for-everyone media cleanup, and backend logs for push/media decisions.
