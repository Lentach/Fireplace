# The media-authorization fix and the identity-banner fix are live on both tiers; the E2E claim now has a measured gap list

**Date:** 2026-09-14 · **Version:** 0.2.47 → 0.2.48 · **Tiers deployed:** both

## What was done
- Deployed `1f05e3e6` to production — both halves. Backend: `chat-message.service.ts` `handleDeleteMessage` now refuses a non-sender BEFORE `mediaCleanup.deleteMediaFile`, so a recipient can no longer destroy the sender's blob. Frontend: the empty-chat `PeerIdentityChangedRow` clears `GlassTopBar`.
- Proved attachments are encrypted **client-side**, three independent legs (provenance / server-never-encrypts / bytes-already-ciphertext). Closes the "media encryption unverified" gap from the earlier session.
- Audited E2E completeness with 7 parallel scouts, every claim re-verified by hand; three scout claims were wrong and are recorded as corrections in the audit file.
- Filed the gap list at `docs/audit/2026-09-14-e2e-gap-audit.md` — **local, untracked** (`.gitignore:85`), because it names unpatched weaknesses of a live deployment. It carries a Handling line: never copy its specifics into tracked files.
- Corrected two over-claims made to the owner mid-session: peer key change BLOCKS sends (it is not an advisory banner), and the ghost-device attack is closed by the DAK-signed device list.

## Key files
- Edited: none in `backend/src` or `frontend/lib` this session — the code fix was committed earlier as `1f05e3e6`; this session deployed and verified it.
- New: `docs/audit/2026-09-14-e2e-gap-audit.md` (untracked by design).
- Read only (load-bearing): `docs/audit/2026-07-07-metadata-privacy-audit.md` (the metadata authority — D1–D21/L1–L9/T1–T6; the new audit defers to it and adds deltas only), `deploy-web.ps1`, `.omp/rules/production-vm-deploy.md`.

## Verification
- **Backend deploy:** `./deploy-backend.sh` on the VM. `fireplace-db-1` NOT recreated; health `starting → healthy` in 10 s. `/version` → `0.2.48 / eefc44b0`. `/health` → `{"status":"ok","db":"ok"}`. Decisive check: the guard string `Only the sender can delete for everyone` appears **2×** in `dist/chat/services/chat-message.service.js` inside the RUNNING container — the fix executes, it is not merely committed.
- **Web deploy:** `deploy-web.ps1` → `PUBLISHED_OK`, exit 0, no Kaspersky exit-21. Smoke **5/5**, including `main.dart.js` contains `eefc44b0` (the only real stale-bundle detector) and app-boot render.
- **CI:** 6/6 on the code-bearing commit `1f05e3e6` (backend tests, Flutter tests, 3 E2E probes, CodeQL). Master's tip `eefc44b0` is docs-only, so `paths-ignore` leaves it with 1 row — check the code commit, not the tip.
- **Attachment encryption:** 24 blobs on the dev volume, all predating the session (newest `2026-09-05 01:47:59`, zero dated `2026-09-14`); entropy 7.999 bits/byte; no JPEG/PNG/GIF/PDF/ZIP/RIFF/Ogg magic and no `JFIF`/`Exif`/`IHDR`/`ftyp`/`moov` in-file; `createCipheriv` absent from all of `backend/src`.
- **NOT verified:** iOS; the owner's installed `0.2.47` APK (unaffected by a web deploy); `for_me` soft-hide on real devices; whether `blockUser` / `deleteConversationOnly` / `clearChatHistory` authorise before unlinking media; any cryptographic review of the libsignal port.

## Notes for next session
- **Owner-owed:** the PWA must be fully closed and reopened on the phone to pick up `0.2.48` (never uninstall — that wipes Signal keys).
- **Highest-value follow-up:** the missing-authorization defect fixed in `handleDeleteMessage` is a CLASS. Three sibling paths (`blockUser`, `deleteConversationOnly`, `clearChatHistory`) have never been checked for the same order-of-operations bug.
- Traps (also in `docs/agents/traps.md`): `deploy-web.ps1` runs an unconditional `flutter clean` that endangers a sibling session's `frontend/build/` artifacts; `powershell -File` under bash returns a FAKE exit code; the VM's git remote still names the pre-rename repo; a backend-only deploy makes `/version` and `/version.json` disagree.
- Read `docs/audit/2026-09-14-e2e-gap-audit.md` before making any claim about how strong the E2E story is — it lists what is proven, what is merely inferred, and what nobody has checked.
