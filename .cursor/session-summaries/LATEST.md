# Latest session summary

**Date:** 2026-07-16 (User card ROUND 3 + 4 — adaptive full-bleed hero, bigger manage-photos sheet, then owner nits: transparent drag proxy, chat-header avatar fills its circle, 44px tab plus — `219dcaa` + `c505049`, **branch-deployed to prod**)

## What was done
On `feat/user-card-rework` (PR #84, still unmerged): owner rejected the round-2 contain-over-blur pillarboxing ("spaces left and right") and called the manage sheet too small. Hero now **sizes itself to the active photo's aspect** — `photoExtent = (width/aspect).clamp(220, max(260, min(width*4/3, 62%·height)))` — so within the clamp the photo fills the full width with ZERO crop and zero bars; extremes get a modest Telegram-style cover crop. Aspects resolved async (`NetworkImage.resolve` + listener, `_photoAspects` map; failures keep the 300 default). Pager simplified: blurred backdrop + contain layer + crossfade DELETED — one `BoxFit.cover` image per page; height changes animate via `TweenAnimationBuilder` around the scroll view. `BoxFit.fill` (distorts) and `fitWidth` (letterboxes landscape) considered + rejected.

Manage sheet: `isScrollControlled`, "Manage photos" title, tray tiles 64px → responsive `((maxWidth-36)/3).clamp(84,148)` via `LayoutBuilder` (~105px on phone), `_PhotoSlot(size:)`, `_ActionRow(large:)` rows. Reorder/set-main/add/delete + optimistic order unchanged.

Round 4 (owner nits, `c505049`): (1) manage-sheet drag proxy white box → `proxyDecorator` transparent Material; (2) chat-header avatar "halo not equal / circle not a circle" — r18 avatar inside a 48w×52h GlassPill → new bare `GlassTopBar.avatar` slot, photo fills the 52px circle Telegram-style ([INFERENCE] surface identified by geometry, not reproduced — confirm with owner); (3) chats-tab plus GlassCircle 52 → 44 (matches user-card action circles).

## Key files
- `frontend/lib/screens/user_card_screen.dart` (aspect resolver, `photoExtent` delegate param, single-cover pager, sheet rework), `test/screens/user_card_screen_test.dart`, `test/preview/user_card_preview.dart` (mixed-aspect photos 1:1 / 2:3 / 12:7).
- Full write-up: `2026-07-16-session-user-card-round3.md`.

## Verification
- `flutter analyze` 0 issues; **full suite 729 passed**. Collapse test now pins "single cover image, no contain/backdrop"; reorder test measures tile pitch (`getSize + 12`) instead of hardcoding 74px. Test images never load ⇒ adaptive extent stays 300 in widget tests — adaptive path verified visually only.
- Harness 390×844: square → 390px hero, portrait → clamped 520px (slight crop), landscape → 228px uncropped; sheet correct in dark + light.
- Lint trap: `LayoutBuilder`'s `context` param shadowing the State's `context` breaks the `mounted` guard for `use_build_context_synchronously` → param renamed `_`.

## Notes for next session
- Rounds 3+4 committed (`219dcaa`, `c505049`) + pushed + **branch-deployed to prod** (`/version.json` 0.0.120, bundle contains `c505049`, smoke PASSED). **`deploy-web.ps1` ran CLEAN twice — no exit-21; owner's Kaspersky exclusions likely fixed it.** Version deliberately kept at 0.0.120 (PR's unreleased version until merge; footer sha disambiguates). **Prod backend still master 0.0.118 — drag-reorder fails loudly on prod until merge.**
- Owner device confirmations pending (round-3 hero feel, sheet size, bug-3 keyboard, tap zones) → merge PR #84 (explicit OK) → master deploy web + backend (migration 0008 + reorder endpoint).
- If styles settled: delete `UserCardStyle.glassPanels`/`auroraTint` + `?style=` switch before merge.
- Reviewer nit still open: card block-path could pop the underlying chat.

## Previous
- 2026-07-15: User card ROUND 2 — full-picture hero, tap-zone pager, **S2 "Frosted Backdrop" WON** (default style), shared-media strip (cache-only), drag-reorder photos (optimistic + backend `position`/migration 0008/`POST /users/profile-photos/order`), linkified About; crop-at-upload removed. Committed `0087150`, branch-deployed to prod. Full: `2026-07-15-session-user-card-round2.md`.
- 2026-07-16: Landing page prototypes, 3 rounds: fire dropped → **B "Dot Globe" WON** (+drag/Ctrl-zoom) → **round 3 full-page skeleton built, verdict pending**. Prototypes untracked in `docs/design/landing-prototype/`, NOT committed. Next: owner flow verdict → build real `/welcome` (Astro + GSAP + Lenis). Full: `2026-07-16-session-landing-prototype.md`.
- 2026-07-15: User card / profile rework D1 "Telegram Full-Bleed" — branch `feat/user-card-rework` 0.0.120, **PR #84 (SHIP verdict) UNMERGED, branch-deployed to prod at `7ded775`** (ephemeral; reverts on next master deploy). No-photo hero fallback fixed in `7ded775`. iOS PWA device confirmations pending (About-edit keyboard, collapse feel, crop gestures). Per-worktree `deploy-web.ps1` is gitignored — copy from sibling worktree; under agent harness it dies silently (exit 21) between scp and swap — finish with the guarded swap over ssh. Full: `2026-07-15-session-user-card-rework.md`.
- 2026-07-15: "Read more" collapse + toast reposition — **PR #83 MERGED + DEPLOYED, 0.0.119 live**. Full: `2026-07-15-session-msg-collapse-toast.md`.
