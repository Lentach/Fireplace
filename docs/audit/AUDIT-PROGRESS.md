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

### Frontend (priority: E2E + auth + push) — depth: 🔬 deep · 📖 full read · 🔍 pattern-swept
- ✅ F1  Bootstrap (📖) — `main.dart` clean (deep-link drain, Firebase dup-app guard); `firebase_secrets.dart` = TODO placeholders (no committed secrets); config dart-defines.
- ✅ F2  Models (📖) — `message_model` copyWith includes all fields (trap avoided); robust enum/reaction parsing. No findings.
- ✅ F3  Auth + REST (🔬) — **L-14** tokens in plain SharedPreferences (365d refresh); refresh mutex/transient handling solid; no token logging. `api_service` → **H-04** sink.
- ✅ F4  Connection/Socket (🔬) — socket token in `auth` not query (good); reconnect cooldown + zombie-socket resume probe sound. No findings.
- ✅ F5  Conversations (📖) — unread-merge + `hasLoadedConversationsOnce` gate correct; push-freshness heartbeat matches backend. No findings.
- ✅ F6  Messaging provider (🔬 decrypt/send; 📖 events/history/actions) — send uses server-validated mediaUrl (clean); exactly-once latch as documented.
- ✅ F7  E2E crypto (🔬) — **H-03** no identity pinning (silent re-key); **L-10** signed-prekey never rotated; **I-04** RAM cache unbounded. `decryption_failure_policy` excellent (no lossful delete).
- ✅ F8  Media crypto (🔬) — AES-256-GCM fresh key+IV/blob, 20MB cap (strong); `EncryptedMediaUploadService` clean.
- ✅ F9  Friends + Settings providers (📖) — client mirrors server authz; `blockedByUserIds` unmodifiable. No findings.
- ✅ F10 Push/badge (🔬 push_service/SW-channel; 🔍 badge math/cleaner shims) — metadata-only; VAPID default is a public key; no plaintext.
- ✅ F11 Screens (📖 chat_detail/main_shell/auth/settings/privacy; 🔍 rest) — no XSS sinks; url_launcher restricted to `https?://` (text_message_content).
- ✅ F12 Input widgets (🔍) — composer/recording/attachment; no security-relevant sinks; paste staging validates mime+size.
- ✅ F13 Message widgets (🔬 image/voice/file/gif fetch path → H-04; 🔍 bubbles/context-menu) — preview image `isSafeImageUrl`-gated.
- ✅ F14 Other widgets (🔍) — dialogs/tiles/overlays/anti-quantum-note; note dialog encrypts client-side (fragment key).
- ✅ F15 Web platform shims (🔍) — stub/web pairs; no `dart:html` XSS sinks anywhere (grep-confirmed).
- ✅ F16 Misc utils (🔬 link_preview_service.isSafeImageUrl, audio_mime; 🔍 rest) — SSRF image guard reused on decrypt path.
- ✅ F17 Theme + l10n (🔍) — `rpg_theme`, ARB files; no logic/secrets. No findings.

### Service worker / web shell
- ✅ SW1 (🔬) — `web-push-sw.js`: metadata-only, notification text rendered as text (no XSS), numeric id parsing, same-origin message handling. Clean.

### Infra & supply chain
- ✅ I1 (🔬) — **H-02** root container amplification (L-11); **M-07** prod `NODE_ENV=development`; nginx no-CSP (L-12) + 11m body cap (L-13); `.env` gitignored.
- ✅ CI1 (📖) — runs backend tests + flutter analyze/test; **no `npm audit`/dep-scan gate** (I-03).
- ✅ D1 (📖) — modern backend deps; `libsignal_protocol_dart` community port assurance note (I-03). No live audit run.

### Cross-cutting passes (Phase 2)
- ✅ X1 E2E flow — keygen→publish(self-scoped)→fetch(public)→build(**H-03 no pin**)→encrypt→transport(ciphertext only)→decrypt(no lossful delete, strong)→rebuild. Plaintext/keys never cross boundary or get logged.
- ✅ X2 AuthN/AuthZ matrix — every REST endpoint JWT-guarded; every WS handler scoped via `client.data.user.id`. Gaps: **H-01** getMessages (no membership), **M-02** fcm delete (unscoped), **L-07** media-by-UUID, **M-05** WS skips pwChangedAt.
- ✅ X3 Untrusted input — **M-04** SSRF (alt-IP-encoding bypass), **H-02** path traversal, no SQL injection (parameterized + constant interpolation only), no ReDoS (linear regexes). **L-09** messageType not enum-validated.
- ✅ X4 Concurrency/races — **M-01** refresh rotation race; optimistic send exactly-once latch OK; reconnect cooldown OK; decrypt serialized per-sender; push dup-suppress OK.
- ✅ X5 Data lifecycle — account-delete cascade thorough except **L-04** secret_notes; media GC + per-minute expiry cron OK (but feeds **H-02** sink); used-OTP rows never pruned (info).

---

## Findings tally
- **Critical:** 0
- **High:** 4 — H-01 getMessages IDOR · H-02 mediaUrl path-traversal file delete · H-03 no E2E
  identity pinning (server MITM) · H-04 access-token exfil via attacker media URL
- **Medium:** 7 — M-01 refresh rotation race · M-02 unscoped fcm-token delete · M-03 prod
  `synchronize` gate · M-04 link-preview SSRF · M-05 WS skips pwChangedAt · M-06 deep-pagination
  memory · M-07 prod `NODE_ENV=development`
- **Low:** 14 (L-01 … L-14) · **Info:** 4 (I-01 … I-04)

---

## Coverage statement

**100% of the planned audit chunks were audited** (all marked ✅ above), at the risk-weighted depth
the user approved. Depth legend used in the frontend list: 🔬 deep line-by-line · 📖 full read,
lighter analysis · 🔍 read + targeted security-pattern sweep.

- **Backend (100 source files):** every domain module, the WS gateway + all 10 chat services, DTOs/
  validators/guards, entities, mappers, crypto-relevant utils, and all cron/cleanup services were
  read in full and analyzed deeply. **No backend source file was skipped.**
- **Frontend (177 files):** all security-critical files (E2E crypto, auth/token, socket/connection,
  messaging decrypt+send, media crypto, push/SW, api_service) were read line-by-line (🔬). Providers,
  models, bootstrap, and the main screens were fully read (📖). Leaf UI widgets, theme, l10n, and
  platform stub/web shims were read at sweep depth (🔍) and additionally verified via repo-wide greps
  for: web XSS sinks (`dart:html`/`innerHtml`/`eval` — none), dangerous URL schemes (links restricted
  to `https?://`), committed secrets (none — placeholders only), plaintext/key/token logging (none),
  and every `fetchMediaBytes` call site (→ H-04).
- **Infra & supply chain:** Dockerfiles, both compose files, nginx.conf, deploy.sh, `.env` handling,
  and CI were read in full. Dependencies were reviewed statically (versions/maintenance); **a live
  `npm audit` / `flutter pub outdated` was NOT executed in this pass** (sandbox/offline) — flagged in
  I-03 as the one item to run to close the dependency-vuln question.
- **Cross-cutting passes X1–X5** were completed against the full picture (see above).

**Not separately deep-audited (deferred, low risk):** test suites (`*.spec.ts`, `frontend/test/**`)
were used as evidence/confirmation but not audited as product code; generated files
(`l10n/app_localizations*.dart`, `firebase_options.dart`) were skimmed; build artifacts
(`dist/`, `build/`, `coverage/`, `node_modules/`) were excluded by design.
