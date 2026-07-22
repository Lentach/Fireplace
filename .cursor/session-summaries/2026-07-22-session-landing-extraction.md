# Session — landing Rev 16 (hero Done pointerdown) + extraction to its own repo

**Date:** 2026-07-22
**Repo:** `C:/Users/Lentach/Desktop/fireplace-ping-deploy` · branch `master`, plus NEW repo `Lentach/fireplace-landing`

## What was done

### 1. Rev 16 — hero terminal Done (`.enc-done`) fixed (owner: Android hides keyboard but button stays; iOS does nothing)
Full write-up: `2026-07-20-session-landing-nits.md` Revision 16. Short version: the old
`click` handler had two bugs — Android Chrome focuses a tapped `<button>` so the pill held
its own `.enc-port:focus-within` visibility open; iOS Safari needs `blur()` inside a real
touch gesture. Ported the Rev-15 pattern: `pointerdown` + `preventDefault` +
`stopPropagation` + `input.blur()`, plus a 500ms `doneAt` suppress window in the port's
focus-on-click handler (the trailing click retargets to the port once the pill hides
mid-gesture and would reopen the keyboard). Verified on live prod with trusted
`elementHandle.tap()` @390×844: focus→BODY, pill hidden, no refocus. Deployed:
JS `BBHOwiQk`, CSS `DJ-65XJU`. Monorepo commit `180c5b9`.

### 2. Landing extracted to its own repo (owner ask: "website lives separately")
- `git subtree split -P landing` → 67 landing commits, history preserved (tip = Rev 16).
- Created **private** `Lentach/fireplace-landing`, pushed split as `master`.
- Local clone: `C:/Users/Lentach/Desktop/fireplace-landing` (landing content at repo ROOT now).
- Added there: `.github/dependabot.yml` (npm monthly, grouped, mirrors monorepo policy),
  repo `CLAUDE.md` (stack, build/deploy gotchas, iOS keyboard-dismiss lore), de-monorepo'd
  README (`cd landing` steps gone; notes the extraction + that the PWA lives in the main repo).
  Commit `7c7d126`, pushed.
- **Deploy pipeline proven from the new repo**: `deploy-landing.ps1` run from its new home
  built and shipped byte-identical assets (`BBHOwiQk`/`DJ-65XJU`) — script was already
  self-contained (`$PSScriptRoot`, VM hardcoded).
- Monorepo: `git rm -r landing`, pointer added to root `CLAUDE.md` §2, `landing-split`
  branch deleted.
- Desktop had a PRE-EXISTING `fireplace-landing` dir — an old monorepo **worktree** on
  `feat/landing-page` (fully pushed, nothing unpushed). Renamed to
  `fireplace-landing-OLD-stale-clone` + `git worktree repair` so the name was free for the
  new clone. Safe to delete later (owner's call): `git worktree remove` it.

## Key files
- NEW repo `Lentach/fireplace-landing` (everything under old `landing/`).
- Monorepo: `landing/` REMOVED; `CLAUDE.md` §2 pointer; this summary.
- New repo: `CLAUDE.md`, `.github/dependabot.yml`, `README.md`.

## Verification
- Rev 16: trusted tap on live prod → activeElement BODY, `.enc-done` display none,
  status Ready, no refocus after 400ms, port tap after window refocuses; 0 console errors.
- Extraction: deploy from new repo → PUBLISHED_OK + identical live hashes; `git log`
  in new repo shows full landing history.

## Notes for next session
- ALL landing work now happens in `C:/Users/Lentach/Desktop/fireplace-landing`
  (repo `Lentach/fireplace-landing`, branch `master`). The monorepo has NO landing dir.
- New repo made **PUBLIC** per owner + business-card README (`2e2e492`): og.png banner,
  Fireplace pitch, page anatomy table, honesty rules, dev/deploy, nginx in `<details>`.
  Homepage + topics set via `gh repo edit`. Full history secret-scanned clean BEFORE the
  flip; accepted exposure: deploy script + repo CLAUDE.md publish `ubuntu@51.68.138.13` +
  `~/fireplace` layout (key-only SSH, stock Ubuntu user, IP already in DNS).
- Dependabot PR #1 there (Astro 7.1.0→7.1.3) merged within minutes of going public;
  rebuilt + redeployed from the new repo — asset hashes UNCHANGED (`BBHOwiQk`/`DJ-65XJU`),
  content-hashed so prod bytes are identical; repo==prod and the owner's pending on-device
  Rev-16 test target is untouched.
- Still awaiting owner on-device iPhone/Android re-test of Rev 16 (hard-refresh first).
  Fallbacks held: (A) Enter-dismiss on journey composers, (B) readonly-toggle before blur.
- Dependabot in the new repo: enable Settings → Code security alerts there (config alone
  doesn't turn on security PRs).
