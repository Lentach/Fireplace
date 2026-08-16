# HANDOFF — video/UX session (0.1.11 + 0.1.12), open threads and traps

**Date:** 2026-08-16 (written at session end, after the 0.1.12 deploy)
**Read me when:** picking up anything touching the composer, media messages, the quantum-note reveal, deploys, or when coordinating with the parallel auth-token session.
**Companion detail file:** `2026-08-16-session-video-ux-batch.md` (full per-item account + verification ledger). This file is the forward-looking part only.

## 1. What is LIVE right now (verified, not inherited — but re-verify if you deploy)

- **Frontend `0.1.12 / d720d16`** — deployed ~18:50Z, smoke 5/5, bundle-commit check passed. Ships: video messages end-to-end, unified media picker (Gallery photos+videos / paperclip docs-only / Camera → Photo|Video mode sheet), staged-video composer flow, composer motion (keyboard ease-down + emoji panel slide), PeerIdentityChangedBanner deleted, 180ms pop fade, PL theme renames (Grafit/Alabaster/Turkus/Błękit/Kosmos), quantum-note in-app reveal, restyled default toast, audio-cache button removed.
- **Backend `0.1.11 / 91535317`** — deployed earlier same day; migration `0012` applied on prod (`messages_messagetype_enum` now has `VIDEO`). 0.1.12 was frontend-only BY DESIGN; the backend version lag is correct, not drift.
- Wire contract addition: `messageType: 'VIDEO'` is first-class on both tiers. Client policy: 20 MB / 60 s / MP4-H.264 (.mp4/.m4v/.mov), enforced at the composer staging seam (`chat_input_bar.dart` `stagePickedVideo`) with toasts `videoTooLarge/videoTooLong/videoUnsupportedFormat`.

## 2. OPEN — things the next agent may actually have to act on

1. **Owner's retroactive device check on the composer motion.** He ordered the 0.1.11 ship before doing the promised iPhone/Android-PWA A/B of the two banned-zone animations. If he reports flash/void/jank: the revert is surgical — keyboard ease lives ONLY in `chat_composer_viewport.dart` (dismiss-slide controller + Transform.translate), emoji slide ONLY in `chat_input_bar.dart` (`_emojiPanelOccupiesLayout` + SlideTransition wrapper). Both degrade to today's pre-0.1.11 behavior under reduce-motion, which is also the shape of the revert.
2. **`deploy-web.ps1` exit-21 silent publish halt — now 6-for-6 from this agent shell.** Build always succeeds; the log ends at the `=== Publish via ssh/scp ===` banner; exit code 21; nothing publishes. The manual staged publish works verbatim every time:
   `ssh VM "rm -rf ~/web-staging && mkdir -p ~/web-staging"` → `scp -r frontend/build/web VM:web-staging` → `ssh VM 'test -f ~/web-staging/web/version.json && cd ~/fireplace && rm -rf frontend-build && mv ~/web-staging/web frontend-build && chmod -R a+rX frontend-build && echo PUBLISHED_OK'` → smoke.
   ⚠️ The parallel session has `deploy-web.ps1` DELETED in its working tree — they may be rewriting it. Check `git log -- deploy-web.ps1` and their branch before root-causing independently or you will collide.
3. **Phase-2 candidates the owner half-opened (do NOT build unasked):** (a) custom getUserMedia in-app camera with swipeable Photo↔Video — the only way to get the Telegram camera feel in a PWA; owner accepted the mode-sheet ceiling for now. (b) Video poster thumbnails — the E2E envelope already carries `mediaWidth/mediaHeight/mediaThumbHash` (unused for video); `shared_media_section` also has no video thumbnails (deliberately out of scope in PR #140). (c) The pre-0.1.11 fingerprint-verification UX the owner rejected — the banner is GONE by his explicit ruling (pushback recorded); detection state + peer-card "Verify security keys" door survive. Do not resurrect the banner.

## 3. Parallel-session coexistence (ACTIVE as of writing)

- Another live agent session owns `C:/Users/Lentach/Desktop/Fireplace` (was on `feat/auth-token-tristate`, later back on master) and merged PRs #138/#139 while this session ran. **Never `git add -A` / commit / checkout in the main tree without reading `git status` FIRST** — this session got burned once (their WIP swept into a commit; caught pre-push, recovered via `git reset --mixed HEAD~1`).
- **Work from throwaway `git worktree`s at exact commits** (`git worktree add C:/tmp/<name> origin/master`). Traps: worktrees lack gitignored `deploy-web.config.ps1` (copy it in) and `scripts/smoke/node_modules` (run smoke from the main clone).
- The dev docker stack is shared. They restarted the backend mid-verification and JWTs started failing `invalid_signature` (their env exports a different `JWT_SECRET` than the root `.env` fallback). If browser-session sends suddenly 401 on `/media/upload`, suspect stack churn BEFORE suspecting the code.
- Test-count line in CLAUDE.md §3 is contested state: it moved 1302→1307→1308→(mine)1314 in one day. NEVER derive it by arithmetic across a merge — measure on the exact tree. The old "Windows one fewer than CI" note proved transient and was removed.

## 4. Verification recipes proven this session (reuse, don't rediscover)

- **E2E video/browser harness:** two REAL clients needed — a headless socket.io peer has no Signal key bundle and every send fails `Recipient has no key bundle`. Isolate the second client via `browser.createBrowserContext()` (own localStorage). Port = origin: the dev app on :8123 vs :8124 sees DIFFERENT localStorage — keep one port or you orphan the Signal keys.
- Flutter semantics in the headless browser: click `flt-semantics-placeholder` first, then `tab.observe()`; canvas text selectors never work.
- Generate a real H.264 test MP4 in-browser: canvas.captureStream + MediaRecorder `video/mp4;codecs=avc1` (Chrome-for-Testing supports it), 3 s ≈ 20 KB.
- Diagnose client-side send failures from `localStorage['flutter.e2e_diag_persist_v1']` (SEND_FAIL entries carry the exception) — faster than console plumbing.
- omp harness: `flutter`/`docker` supervised processes need `cmd.exe /c` wrappers; PowerShell via `-ExecutionPolicy Bypass -File` (never inline `-Command`, the bash tool mangles `$`); subagents ≤2 concurrent (6 tripped the Anthropic per-minute limit and died MID-EDIT — auditable partial state, resume batches with explicit "audit then complete" briefs); `modelRoles.task` must stay on an Anthropic model (owner has no Codex quota).

## 5. Loose ends (small, deliberate)

- Dev DB (local only): accounts videotest1/85, videotest2/86 with a VIDEO/VOICE/TEXT history and one failed-send row — harmless, reusable for the next media test.
- `hub` process `devstack` (dev docker compose) may still be running from this session; it dies with the last omp exit. The other session also drives the same compose project — do not `docker compose down` without checking with them.
- `feat/video-ux-batch` branch was auto-deleted on merge; `feat/media-picker-redesign` deletion at merge printed a local worktree error — verify `git branch -r` and prune if it survived.
- The owner-facing reminder that never expires: after any web deploy, fully close + reopen the PWA; NEVER uninstall or clear site data (kills Signal keys).
