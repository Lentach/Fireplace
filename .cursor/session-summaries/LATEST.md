# Latest session summary

**Date:** 2026-07-15 (User card ROUND 2 — owner feedback batch: full-picture hero, tap-zone pager, frosted-glass restyle **S2 WON**, shared media, drag-reorder, linkified About — committed `0087150`, **branch-deployed to prod**)

## What was done
On `feat/user-card-rework` (PR #84, still unmerged): implemented the owner's round-2 feedback. Crop-at-upload REMOVED (`avatar_crop_screen.dart` + `crop_your_image` deleted) — hero shows the full picture (contain over blurred backdrop, crossfades to cover during the collapse morph). Gallery swipe replaced by tap zones (left=prev/right=next, wraps). Copy-tag tile removed (hero icon + tap-on-handle only). Body restyle: 3 glass directions behind `UserCardStyle`; owner picked **S2 "Frosted Backdrop"** (blurred primary photo washes the body; true backdrop-blur `GlassSurface` sections) — now the default; S1/S3 kept for iteration, strip at merge.

New: shared-media strip (E2E ⇒ RAM-cache-only via new `MessagingProvider.cachedMessagesFor`; `UserCardVisualData.conversationId` plumbed), drag-reorder photos (optimistic tray + backend `position` column, migration 0008, `POST /users/profile-photos/order`, first id = main), linkified About (`lib/utils/linkify.dart`, shared with chat text). Mute durations found ALREADY shipped end-to-end — nothing built. Skipped per owner: QR, last-seen; notification-override explained + skipped.

## Key files
- `frontend/lib/screens/user_card_screen.dart` (hero pager, tap zones, `UserCardStyle`, `_StyledPanel`, `_AmbientBackdrop`, optimistic reorder sheet), `lib/widgets/user_card/shared_media_section.dart`, `lib/utils/linkify.dart`, `api_service.dart`, `auth_provider.dart`, `messaging_provider.history.dart`, `contacts_screen.dart`, `chat_detail_screen.dart`, ARBs.
- Backend: `users.{service,controller}.ts`, `profile-photo.entity.ts`, `dto/reorder-profile-photos.dto.ts`, `migrations/0008_user_profile_photo_position.sql`.
- Renders: `docs/design/user-card-rework/round2/`. Full write-up: `2026-07-15-session-user-card-round2.md`.

## Verification
- `flutter analyze` 0 issues; **full suite 729 passed** (card tests rewritten for tap zones; reorder test asserts persisted `[2,1,3]` — catches newIndex off-by-one; collapse-crossfade test added — caught + fixed an FP bug where `morphT` never reached exactly 1, leaving a ghost contain layer mounted at full collapse). Backend targeted specs 7 green.
- Visual loop (harness 8123, frosted): dark/blue/light/teal × other/self/noPhoto all correct.
- Trap: hot-restart `R` sent in the same parallel batch as an edit compiles the pre-edit tree (stale byte-identical screenshots). `hub start` on Windows needs `cmd /c flutter`.

## Notes for next session
- Round 2 committed (`0087150`) + pushed + **branch-deployed to prod** (`/version.json` 0.0.120, bundle contains `0087150`, smoke PASSED; deploy-web.ps1 exit-21 trap hit again → manual guarded swap). **Prod backend is still master 0.0.118 — drag-reorder will fail loudly on prod (endpoint + position column ship at merge via deploy-backend.sh); everything else testable now.** Owner iOS confirmations pending → merge PR #84 (explicit OK) → master deploy web + backend.
- If no round-3 style iteration: delete `UserCardStyle.glassPanels`/`auroraTint` + `?style=` switch before merge.
- Reviewer nit still open: card block-path could pop the underlying chat.

## Previous
- 2026-07-16: Landing page prototypes, 3 rounds: fire dropped → **B "Dot Globe" WON** (+drag/Ctrl-zoom) → **round 3 full-page skeleton built, verdict pending** (globe hero → light product reveal: annotated phone + live server-ciphertext ticker → feature trio → honest ledger → dark outro; competitor refs zangi/wire/session judged "mid, we do better"; "open source" claim downgraded to "public source" — repo public but NO LICENSE file). Prototypes untracked in `docs/design/landing-prototype/`, NOT committed. Next: owner flow verdict → build real `/welcome` (Astro + GSAP + Lenis). Full: `2026-07-16-session-landing-prototype.md`.
- 2026-07-15: User card / profile rework D1 "Telegram Full-Bleed" — branch `feat/user-card-rework` 0.0.120, **PR #84 (SHIP verdict) UNMERGED, branch-deployed to prod at `7ded775`** (ephemeral; reverts on next master deploy). No-photo hero fallback fixed in `7ded775`. iOS PWA device confirmations pending (About-edit keyboard, collapse feel, crop gestures). Per-worktree `deploy-web.ps1` is gitignored — copy from sibling worktree; under agent harness it dies silently (exit 21) between scp and swap — finish with the guarded swap over ssh. Full: `2026-07-15-session-user-card-rework.md`.
- 2026-07-15: "Read more" collapse + toast reposition — **PR #83 MERGED + DEPLOYED, 0.0.119 live**. Full: `2026-07-15-session-msg-collapse-toast.md`.
- 2026-07-15: Deferred §9 visual pass + polish + bright-accent contrast fix; **PR #81 MERGED + DEPLOYED, 0.0.117 live**. Full: `2026-07-15-session-glass-dialog-visual-pass.md`.
