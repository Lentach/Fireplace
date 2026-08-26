# 2026-08-26 — camera/file RETURN legs verified green; 4-day-standby recovery playbook; host-lag root cause was a runaway thumbnail dllhost

**Date:** 2026-08-26

## What this session was

Retry of the single unverified item from `2026-08-21-session-composer-fix.md`: the
camera/file door RETURN leg of branch `fix/composer-regression` (PR #151). Both legs
are now **GREEN end-to-end on the emulator**; the 08-21 failures are confirmed
environmental. Docs updated in `d367098`; this file adds the operational knowledge.

## Verification result (evidence: `local/probe/m1..m15.png`, untracked)

- **Camera leg:** paperclip → sheet → Aparat → emulator camera → shutter → confirm →
  staged chip (`…966.jpg · 62 KB`, page NOT cold-booted) → send → encrypted IMAGE
  delivered (bubble ✓, `messages` row id 2 with mediaUrl).
- **File leg:** paperclip → sheet → Plik → Files "Recent" → `fp-probe.txt` → FILE
  message delivered (bubble ✓, row id 3).
- Keyboard rose after both flows (symptom K clean). Zero page reloads mid-flow.
- Recipe that worked: **default-GPU** Pixel_7, fresh cold boot, idle host.
  swiftshader crashes at boot; `-feature -Vulkan` boots but Chrome ANR-loops forever
  (CPU raster cannot drive CanvasKit) — both configs are dead ends, do not retry them.

## 4-day-standby recovery playbook (what breaks and how to restart)

1. `fpcomposer` containers die with the Docker host (backend exit 137). Restart db
   FIRST, then backend.
2. **Backend takes ~5 minutes to become healthy** in watch mode (npm check → tsc
   watch compile ~70 s → Nest boot) and the docker log stream can lag the process by
   minutes. **Poll `GET /health` for up to 8 min; NEVER conclude "hung" from silent
   logs.** This session `kill -9`'d a HEALTHY `dist/main` on that misread — and
   `nest start --watch` does NOT respawn a killed child (only a file change does);
   recovery is `docker restart` + patient poll.
3. Access tokens expire over the gap but the **refresh token holds** — the probe
   Chrome profile logs back in by itself; no reseeding, no manual login.
4. adb reverses (`tcp:8095`, `tcp:3000`) must be re-established after every emulator
   boot; the static server survives on the host.

## Host-lag root cause (measured, not guessed)

- qemu is properly WHPX-accelerated: **6% CPU at idle** (checked with
  `emulator -accel-check` + 5 s CPU deltas). RAM was fine (5.6/16 GB free).
  Do NOT cap AVD cores — that advice was considered and withdrawn as harmful.
- The actual burner was a **runaway thumbnail-cache dllhost**
  (CLSID `{DFB65C4C-B34F-435D-AFE9-A86218684AA8}`), alive ~24 h, 1,400 s CPU,
  driving total CPU to 55–69% and **kernel time to 47%** via the AV filter driver.
  Killing it dropped the box to total 20% / kernel 5%. Trigger unidentified (a
  0-byte-screenshot theory was retracted — the file postdated the process).
  **If the emulator lags again: check `dllhost` in Task Manager Details FIRST;
  kill it (respawns clean) before restarting anything.**
- Screenshot-pile hygiene: 0-byte captures deleted, remaining images verified
  intact. Next probe session should write screenshots outside indexed paths
  (e.g. `C:\tmp\probe`) instead of the worktree.

## State at close

- Branch `fix/composer-regression`, HEAD `371293c` (merge of master's docs-only
  drift; conflict in LATEST.md resolved keeping both intents), pushed. PR #151
  CI 6/6 green ON THE MERGED TREE, mergeable, **NOT merged**, no version bump.
  Independent reviewer verdict: SHIP-WITH-NITS, no blockers (2 code nits left
  deliberately unfixed to preserve the banked emulator verification).
- **⚠️ PROD IS SERVING THE UNMERGED BRANCH BUILD** (owner ordered a branch-test
  deploy per the runbook's "Branch testing before merge"): frontend `0.1.19 ·
  371293c` published via `deploy-web.ps1`, smoke PASSED rc=0 (bundle sha check
  green), backend untouched (0.1.11/9153531). Whatever happens next, prod must
  end on a master build: iPhone test passes → merge #151 + PATCH bump + normal
  deploy; fails → `git checkout master ; .\deploy-web.ps1` rollback.
- **⚠️ Main checkout `Desktop/fireplace` is left in DETACHED HEAD at `371293c`**
  (the branch itself is held by the `fireplace-composer` worktree). Before any
  `git pull` or deploy from that checkout, `git checkout master` first — a blind
  deploy from there silently re-ships the branch build.
- **Single merge gate left:** owner iPhone — paperclip with keyboard DOWN → menu
  anchored near the paperclip, no orb/flash. Android real-device pass is a bonus.
- Rig fully torn down (emulator, `fpcomposer` compose project removed, :8095
  server stopped). `C:/tmp/fp-repro` left untouched.
