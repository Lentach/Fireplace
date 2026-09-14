# Delete-for-everyone proven irreversible on devices; a recipient could destroy the sender's media file

**Date:** 2026-09-14 · **Version:** unchanged (0.0.2 dev / prod 0.2.47) · **Tiers deployed:** none

## What was done

- Drove the whole delete path on real clients (Android emulator debug APK + a second live web client on the dev stack) and captured server, wire and on-device state before/after. Text message 974 and media message 976 both hard-deleted; 977/978 used for the bug below.
- Found and fixed a data-destruction bug: `chat-message.service.ts` `handleDeleteMessage` unlinked the media file (line ~1004) BEFORE the sender check inside `deleteById`, with only conversation membership gating the handler — a RECIPIENT emitting `deleteMessage {mode:'for_everyone'}` destroyed the sender's file on disk, got `Only the sender can delete for everyone`, and left the row with a dangling `mediaUrl`. The sender check now runs first; media still precedes the row (backend `CLAUDE.md` §8).
- `docs/contracts/wire.md` delete-semantics line now states that sender-only covers the media unlink.
- Fixed the owner-reported UI bug: in an EMPTY chat the `PeerIdentityChangedRow` painted UNDER the floating `GlassTopBar` (back button/title/avatar over it). `_buildMessagesArea` cleared only the status bar; the empty-state branch now uses `emptyTopClearance = padding.top + GlassTopBar.capsuleHeight + 16`, the formula the other GlassTopBar screens use. The reverse list is untouched (its content anchors at the bottom).
- Two regression tests: Flutter widget test asserts the row's top ≥ the rendered `GlassTopBar` bottom; Jest test asserts a non-sender's `for_everyone` never calls `deleteMediaFile`. Both proven red against the pre-fix code.

## Key files

- Edited: `backend/src/chat/services/chat-message.service.ts`, `backend/src/chat/services/chat-message.service.spec.ts`, `frontend/lib/screens/chat_detail_screen.dart`, `frontend/test/screens/chat_detail_identity_row_test.dart`, `docs/contracts/wire.md`, `CLAUDE.md` (§3 counts 1126→1127, 2143→2144).
- Read only (load-bearing): `backend/src/messages/messages.service.ts` (`deleteById`, `findByIdWithConversation`), `backend/src/media/{media-cleanup,local-storage}.service.ts`, `frontend/lib/providers/encryption_provider.dart` (`purgeLocalPlaintext`, `diagStorageSets`), `frontend/lib/widgets/glass/glass_top_bar.dart`.
- Evidence: `.planning/delete-proof/` (42 screenshots, untracked).

## Verification

- Live drive, dev stack, emulator-5554 debug APK + web client: msg 974 → `messages`=0, `message_envelopes`=0 (envelope 239 cascaded), backend log `User 225 deleted message 974 for everyone`; the peer's OPEN chat dropped the row live; sender's in-app hacker-mode "Storage sets" went `ledger [974] / stored [974]` → `[] / []`; recipient's durable store lost `flutter.e2e_226_decrypted_974` and `…_decrypt_raw_v1_974`. Survived a restart of both clients and a WIPED-storage fresh login (server serves nothing to a clean device). `messages_id_seq` stays at the burned id.
- Media: msg 976 `/app/media/msgs/a383e996….bin` (21 319 B) → `No such file or directory`, dir 25→24.
- Bug + fix, over the wire: pre-fix msg 977 file gone / row intact (and the client then 404s the `mediaUrl` — seen in the backend log); post-fix msg 978 non-sender attempt left the file (6 884 B) AND the row, then the sender's delete removed both.
- `cd backend && npm test` → **62 suites / 1127 tests**; `node scripts/verify-claude-backend-test-counts.mjs --log …` OK; `node scripts/lint-ratchet.mjs` PASS at baseline 898.
- `cd frontend && flutter test` → **2144 passed / 14 skipped**; frontend count verifier OK; `flutter analyze` on both touched files clean of new findings.
- Banner fix verified visually: rebuilt + installed the debug APK, reproduced the empty chat with the alarm, banner now sits fully below the bar (`42-emu-banner-fixed.png`).
- **REAL PHONE (`f849cc68`, owner unlocked it; its 0.2.47 install untouched):** a `flutter build web --release` bundle served on 8089 + `adb reverse`, opened in the phone's Chrome and driven over `adb forward … chrome_devtools_remote` + CDP. Emulator→phone msg **979**: shown decrypted on the handset, then deleted for everyone from the emulator → the phone's OPEN chat dropped it live, `flutter.e2e_227_decrypted_979` + `…_decrypt_raw_v1_979` vanished (45→44 keys), row and envelope 0. Phone→emulator msg **980**, composed and sent ON the phone, then deleted for everyone by the OWNER's own tap: backend log `User 227 deleted message 980 for everyone`, row 0, envelopes 0, both screens empty, and a COLD page reload on the phone brought nothing back.
- NOT verified: iOS; PRODUCTION (the phone leg ran against the dev stack, not prod); `for_me` soft-hide on devices (code-read only).

## Notes for next session

- Phone leg DONE (see Verification) — against the DEV stack via Chrome + CDP, not prod. A production run would still need the owner to tap in the installed 0.2.47 app; prod baseline for that was captured at `max(messages.id)=24404`, 05:16:43Z.
- Owner-owed: shipped as `1f05e3e6` (+ doc fixes `a9fba52b`), CI 6/6 on the tip, but **not deployed** — prod still serves 0.2.47 with the unlink bug until someone runs `./deploy-backend.sh` on the VM. The backend half is separable: `git show 1f05e3e6 -- backend/src/chat/services/chat-message.service*.ts docs/contracts/wire.md | git apply --reverse --check -` passes, so it can be reverted alone if the owner wants it reviewed first.
- NOT-verified surface: whether any OTHER destructive path unlinks media before authorizing (block/delete-conversation/clear-history were not re-audited this session).
- Traps appended to `docs/agents/traps.md`: recipient-unlink ordering, `socketReady` vs `connect` for wire clients, adb via powershell, MIUI keyguard, empty-state top clearance, the CRLF `prettier --check` false signal, CDP-drives-the-real-phone (plus the prod-tab hazard in the target list), and the DDC web-server build never mounting on Android Chrome.
