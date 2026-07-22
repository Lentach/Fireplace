# Latest session summary

**Date:** 2026-07-22 (landing Rev 16 hero-Done fix + landing EXTRACTED to its own repo — now **`Lentach/fireplaceWebsite`**, owner renamed it from `fireplace-landing` same day — the monorepo no longer contains `landing/`)

## What was done
1. **Rev 16 — hero terminal `.enc-done` fixed** (Android: keyboard dismissed but button stayed — the tapped `<button>` held `.enc-port:focus-within` open through itself; iOS: nothing — `click` unreliable with keyboard up, `blur()` only honored inside a real touch gesture). Ported the Rev-15 pattern in `encrypt.ts`: `pointerdown` + `preventDefault` + `blur()`, 500ms suppress so the retargeted click can't refocus. Verified on LIVE prod with trusted `tap()`. Deployed JS `BBHOwiQk` / CSS `DJ-65XJU`, monorepo commit `180c5b9`. Awaiting owner on-device re-test (hard-refresh first).
2. **Landing extraction**: `git subtree split -P landing` (67 commits, history preserved) → new **private** repo `Lentach/fireplace-landing`, local clone `C:/Users/Lentach/Desktop/fireplace-landing` (content at repo ROOT). Added repo `CLAUDE.md`, dependabot, de-monorepo'd README (commit `7c7d126`). **Deploy proven from the new repo** — byte-identical live assets. Monorepo: `git rm -r landing` + CLAUDE.md §2 pointer.

## Key files
- New repo `Lentach/fireplace-landing` (all former `landing/` content + `CLAUDE.md`, `.github/dependabot.yml`).
- Monorepo: `landing/` removed, root `CLAUDE.md` §2 pointer.

## Verification
- Rev 16 on live prod, trusted `elementHandle.tap()` @390×844: tap Done → activeElement BODY, pill hidden, status Ready, no refocus; 0 console errors.
- Extraction: `deploy-landing.ps1` from the new repo → PUBLISHED_OK, identical live hashes `BBHOwiQk`/`DJ-65XJU`.

## Notes for next session
- **ALL landing work now lives in `C:/Users/Lentach/Desktop/fireplace-landing`** (branch `master`); read its `CLAUDE.md` for build/deploy gotchas + iOS keyboard-dismiss lore. Do NOT look for `landing/` in the monorepo.
- Old Desktop `fireplace-landing` dir was a monorepo worktree on `feat/landing-page` (fully pushed) — renamed to `fireplace-landing-OLD-stale-clone`, worktree repaired; owner may `git worktree remove` it later.
- New repo is **PUBLIC** (owner ask, history secret-scanned clean first) with a business-card README: pitch + live-site screenshot gallery (`docs/screens/*.webp`, captured from prod via puppeteer webp screenshots) + regenerated 1200×630 `og.png` social card (old one was the top-strip-cut shot; new one deployed live, JS/CSS hashes untouched). Homepage + topics set. Known-and-accepted exposure: `deploy-landing.ps1`/`CLAUDE.md` publish the VM SSH login `ubuntu@51.68.138.13` + `~/fireplace` layout (key-only SSH; stock Ubuntu user; DNS already resolves the IP). Dependabot live there — PR #1 (Astro 7.1.0→7.1.3) merged within minutes; rebuilt+redeployed, asset hashes UNCHANGED, repo==prod. Still enable Dependabot alerts in its Settings → Code security.
- Full write-up: `2026-07-22-session-landing-extraction.md`.

## Previous
- 2026-07-21: Pre-release audit-fix on branch `fix/audit-bugs` (worktree `fireplace-fixes`), v0.0.123 — R2 chat-detail dedup, backend branch cleanup, FULL test-suite audit (backend 474→534, frontend 727→770), link-preview ULA regex fix, MainShell nav-policy extraction. R1/R3 skipped per owner. **Commit-only — NOT pushed, NOT merged; never push without explicit owner OK.** Owner decisions left: TOFU/safety-numbers, TEMP E2E diagnostics removal, Giphy key rotation, unreferenced binary assets. Full: `2026-07-21-session-audit-fix-refactors.md`.
- 2026-07-20 (+07-22 Rev 16): Landing `/welcome` Rev 7-16 — reduced-motion + rAF pause + SEO meta + a11y + skip bookends; `.kb-done` journey pill dismisses+hides on **pointerdown** (Rev 15); Rev 16: hero `.enc-done` same pattern. Astro 7.1.0 (dependabot #88). LIVE `BBHOwiQk`/`DJ-65XJU`. Full: `2026-07-20-session-landing-nits.md`.
- 2026-07-20: Landing six owner nits + on-device Revisions 2-6. Committed `7aabcea`. Full: `2026-07-20-session-landing-nits.md`.
- 2026-07-19: Landing root-only mobile shrink fix (`footer { overflow-x: clip }`) — LIVE. Full: `2026-07-19-session-landing-mobile-autozoom.md`.
