# 2026-08-16 — §5.4 MERGED: storage errors are not logouts (tri-state token read)

**PR #137 → master `313f764` (commit `2a11848`). CI 4/4. NOT yet deployed** — prod is `0.1.11 /
9153531` (the video batch, deployed 14:20Z, before this merge). Ships with the next release.

## The defect (handoff §5.4 — the last error-as-absence inversion)

`AuthTokenStore.read()` reported ANY storage error as "no tokens"; `auth_provider` then showed a
login screen and — the killer — `_clearLocalAuthState` ran `_tokens.clear()`, DELETING the intact
stored tokens it had merely failed to read. A transient plugin fault became a permanent logout
(user 54's refresh row was valid to 2027 while he sat on a login screen). The identity-side twin
of this inversion shipped as the 0.1.10 guard; this closes the token side. Both platforms: the
defect existed identically on the web/prefs path AND the Android secure-storage path (Keystore
transients) — this is APK-relevant, not PWA-only.

## What changed

- **Store** (`auth_token_store.dart`): `read()` → `({access, refresh, readFailed})`. Three fast
  retries (150/400 ms); persistent failure → `readFailed: true` + durable
  `AUTH_TOKENS_UNREADABLE {errorType, platform}`. `write()` retries once; persistent refusal →
  durable `AUTH_TOKEN_WRITE_FAILED` ("logged out next boot" finally has a paper trail).
- **Provider** (`auth_provider.dart`): boot does bounded retry-before-decide (2 s/5 s slow
  retries, injectable via `tokenReadRetryDelays`); if storage still errors, it concedes to the
  login screen **without touching the store** and sets an honest `statusMessage` ("Could not read
  the saved session…") instead of feigning a logout — no `AUTH_SESSION_END` is fabricated.
- **Reason-scoped clears** (the advisory refinement): `_clearLocalAuthState` gained
  `wipeStoredTokens`. Server-authoritative reasons (`refresh_invalid*`, explicit logout, password
  change) still wipe. The LOCALLY-derived reasons — `expired_access_without_refresh`,
  `access_401_without_refresh` — clear the session but can no longer delete persisted tokens; the
  next cold boot re-reads storage and recovers.
- **Tests (5 new, flutter 1302→1307/10sk):** store tri-state ×3 (persistent error → readFailed +
  diag, never absence; transient error → retried and recovered; refused write → durable diag);
  provider ×2 (unreadable store → truth-telling concession, store untouched, no fake session-end;
  `access_401_without_refresh` → session cleared, store intact, reason still recorded). The
  gitleaks pre-commit gate rejects literal JWTs even as dummy fixtures — build them at runtime.

## Notes

- Known accepted trade-off: an expired access token with genuinely no refresh now lingers in
  storage across boots (each boot restores → one doomed `fetchMe` → session cleared, store kept).
  Harmless dead JWT; a normal login overwrites it. The alternative (deleting) is exactly the bug.
- Found `deploy-web.ps1` deleted from the working tree mid-session (not by this session);
  restored from HEAD. With parallel sessions in one checkout, `git status` before every commit.
