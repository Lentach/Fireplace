# 2026-09-08 (c8) — registration settles itself; text-pass proposal

**Date:** 2026-09-08 (evening, after 0.2.27)

## What was done

- **Diagnosed the friend's "server error" from prod logs, not the screenshot.** IP `31.175.148.17`, iPhone Safari (UA carries `Safari/604.1` — a browser TAB, never the installed PWA). 19:03 UTC loads the app; nothing reaches nginx for 4 minutes; 19:08:23 `login ___` ×3 (401) + `register ___` (201) arrive in the SAME second; 19:08:25 `login ___` 201 → shell, 15 min of use. Shape: iOS froze the tab's socket while he was in Telegram (the `TELEGRAM` pill), the first POST after resume hung, our 15 s timeout fired and he read `authStatusRegisterOutcomeUnknown` as an outage; everything he tapped afterwards flushed in one burst. Account `___#7868` (id 117) exists. No backend bug; `___` is a valid name (exact-match lookup, no LIKE).
- **0.2.28 (`00ee34e`, web-only):** `AuthProvider.register` settles a lost answer itself — sign in with the same credentials; a refusal proves the server is back and the account is not ours, so the register is retried ONCE (its 409 lands in the existing taken→sign-in branch); only a second lost answer is reported. `login` retries a lost answer once. `AuthStatusCode.registerOutcomeUnknown` and its two paragraphs deleted; `authStatusServerUnreachable` is now `Brak połączenia. Spróbuj ponownie.` / `No connection. Try again.` `_signIn`/`_register` return the classified code (null = success); `_report` is the single status writer for failures.
- **Text-pass proposal drafted, NOT coded** (owner reviews first): `.planning/text-pass/proposal.md` — 68 strings ≥90 chars rewritten to one line ≤70 chars PL, mechanism removed; 6 ICU plurals excluded. Pasted to the owner in chat.

## Key files

- `frontend/lib/providers/auth_provider.dart` — `register`, `login`, `_register`, `_signIn`, `_report`; `classifyAuthFailure` lost → `serverUnreachable` for every attempt.
- `frontend/lib/l10n/app_pl.arb`, `app_en.arb` (+ generated) — key removed, one shortened. `frontend/lib/l10n/auth_status_text.dart`.
- `frontend/test/providers/auth_registration_outcome_test.dart` — group `a lost register answer is settled by the provider` (5) + 2 login retry cases. `test/screens/auth_screen_theme_test.dart` mapping.

## Verification

- Mutants, 1 substitution each, restored, `git diff` clean: F25 `if (false)` on the settle branch → +13 −4; F26 report instead of retry after a refused probe → +14 −3; F27 login never retries → +16 −1. Baseline 17/17.
- Frontend suite 2064 / 14 skipped (`CLAUDE.md` §3 updated, verifier OK). CI 34273754093 green 5/5.
- Live, rebuilt bundle `--dart-define=BASE_URL=http://127.0.0.1:3000`, fresh Chrome profiles, backend `docker pause`d mid-request: **A** register `c8lost` → spinner past 15 s → unpause → shell within 6 s (server log: probe 401, then the flushed register created id 202, retry 409, sign-in 201 — the race path). **B** backend paused throughout → after ~30 s `Brak połączenia. Spróbuj ponownie.`, button re-enabled, exactly one register sent. **C** `c8taken` with the wrong password → taken line + `Przejdź do logowania`.
- Deployed web-only; smoke in `deploy-web.log`.

## Notes for next session

- Worst case is now 45 s of spinner (register 15 s + probe 15 s + retry 15 s) before the one-liner; that is the accepted trade for never showing the paragraph.
- The friend runs Umbra in a Safari TAB: no push, and installing the PWA later = a new device (different storage) → gate → link/restore. Owner told; "fine for now, native app coming".
- Text pass awaits the owner's strikes on `.planning/text-pass/proposal.md`; single release when approved. Ship with a screenshot pass on every touched screen (gate, devices, settings, passcode, notes).
