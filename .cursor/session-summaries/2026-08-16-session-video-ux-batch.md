# Video messages + 8-item UX batch (owner-driven)

**Date:** 2026-08-16

## What was done

Nine owner-requested items, all shipped and verified live on the dev stack (parallel subagent batch; the first batch died to a rate limit mid-edit and was resumed — audit trail in the session transcript):

1. **VIDEO messages, first-class both tiers.** Backend: `VIDEO` in MessageType enum, migration `0012_video_message_type.sql` (ALTER TYPE only — tx-safe on PG16, applied clean on dev boot), `'video'` in upload DTO, content-empty ValidateIf exemption, mapper label, +5 tests. Frontend: `MessageType.video` + both parsers, videocam composer tile (image_picker pickVideo 60s native / file_picker mp4|m4v|mov web), `sendVideoMessage()` (durability ordering copied from voice — keys stashed before await), NEW `VideoMessageContent` (lazy controller on tap, web blob-URL like GIF path, native temp file, revoke/delete on dispose), `video_player 2.14.0` (pins untouched), previews/reply labels/l10n EN+PL. Policy: 20 MB, 60 s, MP4/H.264 only (rejection toasts verified live — PL "Nieobsługiwany format wideo").
2. **Keyboard dismiss ease-down** (`chat_composer_viewport.dart`): compositor-only Transform.translate ~200ms on single-step full drops only; LAYOUT still collapses same-frame (Symptom B contract untouched); reduce-motion instant. ⚠️ Banned-zone exception, owner-approved; **owner device A/B still required before deploy.**
3. **Emoji panel slide** (`chat_input_bar.dart`): 220ms GPU SlideTransition of full-height content, layout reserved from frame 1 (pin semantics unchanged), animated exit on keyboard-neutral closes only; reduce-motion instant. Same device-A/B gate as #2.
4. **PeerIdentityChangedBanner DELETED** (owner ruling; pushback recorded — this was the in-chat MITM alarm). Surviving surface: `peersWithChangedIdentity` state, PEER_IDENTITY_CHANGED diag, and the "Verify security keys" door in the peer card. Widget file + banner tests removed.
5. **Swipe-back/pop lag:** `instant_opaque_route` now has a 180ms reverse FadeTransition (forward stays zero-duration opaque — the mobile-web half-transition guard), `clearMessages()` deferred post-frame with a re-open guard AND an `isDisposed` guard (new `MessagingProvider.isDisposed`; the suite caught a disposed-notify in the honeycomb test — real bug, fixed at source).
6. **Polish theme names:** Grafit / Alabaster / Turkus / Błękit / Kosmos (EN: Graphite / Alabaster / Turquoise / Azure / Cosmos), descriptions rewritten both locales.
7. **"Clear downloaded audio cache" button removed** from Privacy & Safety + 5 dead ARB keys (both locales). Safe: `AudioCacheStore.remove(ids)` fires automatically in the destroy/expiry purge (`encryption_provider.dart:722`). Store/`clearAudioCache` code kept.
8. **Anti-quantum note:** (a) NEW in-app reveal sheet (`anti_quantum_note_reveal_sheet.dart`) — protocol: POST `{origin}/note/{token}/reveal` (public, atomic DELETE RETURNING), AES-256-GCM key from #fragment (base64url 32B, validated BEFORE the destructive POST), `base64(iv):base64(ct||tag)`; confirm-first burn warning, distinct destroyed/expired/corrupt/invalid/network states; foreign-origin links keep external launch. The "Return to Fireplace" cold-boot reboot is gone by construction. (b) Privacy & Safety explainer rebuilt as structured card (lead + 4 glyph rows, split ARB keys). Also fixed a pre-existing 4.1px right overflow on the delete-all button (Flexible+FittedBox).
9. **Top snackbar default restyle:** default fill was `inverseSurface` (near-white on dark themes) → now `surfaceContainerHighest` + 1px outlineVariant border + onSurface text + leading info icon. Explicit-color callsites byte-identical.

## Key files

Backend: `message.entity.ts`, `migrations/0012_video_message_type.sql`, `upload-media.dto.ts`, `media.controller.ts`, `chat.dto.ts`, `message.mapper.ts`. Frontend: `message_model.dart`, `messaging_provider(.send).dart` (+`isDisposed`), `chat_action_tiles.dart`, `video_message_content.dart` (NEW), `video_{blob_url,probe,temp_file}_*.dart` (NEW), `message_content_factory.dart`, `chat_composer_viewport.dart`, `chat_input_bar.dart`, `instant_opaque_route.dart`, `chat_detail_screen.dart`, `anti_quantum_note_reveal_sheet.dart` (NEW), `anti_quantum_note_link.dart`, `anti_quantum_note_card.dart`, `text_message_content.dart`, `api_service.dart`, `privacy_safety_screen.dart`, `top_snackbar.dart`, both ARBs, `pubspec.yaml`.

## Verification

- `flutter analyze` clean; **frontend 1301/1301 (10 skipped)**, **backend 681/681, 49 suites**; both count verifiers green; CLAUDE.md §3 bumped.
- Live dev-stack browser run (two real clients, isolated contexts, fresh accounts videotest1/85 + videotest2/86): video picked → encrypted → uploaded (`msgs/*.bin`, server row `707|VIDEO|…|3|DELIVERED`) → peer decrypted → **played** (frames visually confirmed); "Wideo" conversation preview; format-reject toast; migration 0012 applied at boot; quantum note composed → in-app reveal sheet (no new tab, pages 6/6) → burn confirmed (`secret_notes` count 0) → card flips to "Notatka zniszczona"; default toast verified on Alabaster AND Grafit; theme names screenshot-verified; emoji panel + action panel + chat-surface-tap dismissal all still behave.
- First video/text sends FAILED with `Recipient has no key bundle` — that was the harness (headless socket peer had no Signal keys), NOT the feature; real-client peer fixed it. Retry path exercised as a bonus.

## Notes for next session

- **The composer motion changes (items 2-3) and everything else here are UNDEPLOYED.** Owner explicitly committed to device-checking the motion on real iPhone/Android PWA before deploy. No version bump yet.
- Committed on branch `feat/video-ux-batch` (NOT master, NOT merged). The commit also carries the previous session's already-authorized §5.1 guard + §5.3 boot-markers work, which was sitting uncommitted in the tree and is inseparably entangled via l10n regen/lockfile; its tests (5 backend + guard/boot-marker frontend tests) are part of the green run above.
- Deploy day checklist: PATCH bump, staging rehearsal NOT required for migration 0012 per §6? — it IS a schema change ⇒ **rehearse on staging first**, then VM `deploy-backend.sh` before/with `deploy-web.ps1` (new client sends VIDEO; old server enum would reject it — deploy backend FIRST).
- `modelRoles.task` in `~/.omp/agent/config.yml` was switched openai-codex → anthropic (owner has no Codex quota; 6 concurrent agents also tripped the Anthropic per-minute limit — resume batches sequentially, ≤2 concurrent).
- Test accounts videotest1/videotest2 + one VIDEO/VOICE/TEXT message remain in the LOCAL dev DB only.
