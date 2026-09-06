# Session — the front door now explains itself (register/login/credential refusals)

**Date:** 2026-09-06 — 0.2.17, master. Follow-up to the diagnosis in
`2026-09-06-session-register-409-diagnosis.md` (a senior dev could not register; the account had
in fact been created and every refusal read "Coś poszło nie tak. Spróbuj ponownie.").

## What was done

**The door had one sentence for every outcome.** `ApiService` threw prose,
`AuthProvider._networkErrorCode` matched five message substrings and mapped everything else to
`unexpectedError`. So 409 taken, 400 shape, 401 wrong password, 429 throttle, 502 mid-deploy and
every transport failure rendered identically — and on WebKit even the one "no connection" branch
could not fire, because `package:http` re-throws the ENGINE's `TypeError` text
(`http-1.6.0/lib/src/browser_client.dart:148-160`) and `Failed to fetch` is Chromium's wording.

Six changes, all client-side (no backend change, no wire change):

1. **`ApiException` (`lib/services/api_exception.dart`)** keeps `statusCode` + the server's
   message. `register`, `login`, `fetchMe`, `resetPassword`, `deleteAccount` throw it via
   `ApiService._fail`. Boot's expired-access branch now type-checks the 401 instead of
   `startsWith('Exception: HTTP_401')` — that string was the only reader and it moved.
2. **`classifyAuthFailure(error, attempt:)`** (top-level in `auth_provider.dart`) maps STATUS →
   `AuthStatusCode`: 400/422 → `usernameInvalid` | `passwordTooWeak`, 401/403 →
   `invalidCredentials`, 409 → `nicknameTaken`, 429 → `tooManyAttempts`, ≥500 → `serverError`.
   Transport is classified by TYPE (`TimeoutException`, `http.ClientException`), never by message.
   `AuthAttempt` picks the per-door reading of the same status.
3. **Registration signs the user in.** `AuthProvider.register` calls the login path on success —
   the credentials are already in hand, and "account created, now sign in" was the step where the
   user got lost. It returns true whenever the ACCOUNT exists; a failed auto-sign-in falls back to
   `registerSucceeded` + a prefilled login tab.
4. **A taken name tries the credentials before it refuses — the friend's case now SELF-HEALS.**
   A 409 is the shape of the lost-response retry: the row exists and the password the user just
   typed is its password. `register` therefore attempts one sign-in on 409; if it opens the
   account, the user lands in the app and reads nothing at all. Only when that sign-in is refused
   (the name is someone else's) does the surface say "already taken" — and then it carries a way
   out: `recoverableUsername` + a "Przejdź do logowania" / "Sign in instead" button
   (`Key('auth-go-to-login')`, register tab only) that switches tabs with the username prefilled.
   Naming the refusal alone is not enough: "that name is taken" still sends the user to invent a
   NEW name, i.e. away from the account they just created. **Not a new oracle:** it is one
   ordinary login attempt, on the same 30/15 min login throttle as the sign-in form, behind the
   stricter 10/h register throttle.
5. **A lost register answer has its own honest wording** (`registerOutcomeUnknown`): the request
   is not idempotent and `Future.timeout` cannot abort it, so the account may exist — the copy
   says to try signing in, and the same recovery button appears.
6. **The rules are stated before they are hit**, and the status stops going stale: the register
   tab shows "3-20 characters: letters, digits and _" / "At least 8 characters, with an uppercase
   letter, a lowercase letter and a digit"; `AuthForm` enforces the server's username rule
   client-side; the status clears on submit and on the first keystroke after it appears (it used
   to clear only on a tab switch, which is why a screenshot showed a `maoi` error under a field
   already retyped to `ma0i`).

Same treatment for the other credential doors: Settings → change password / delete account no
longer print `'${l10n.passwordResetFailed}: $e'`. They share `authStatusText(l10n, code)`
(`lib/l10n/auth_status_text.dart`) with the front door, so "wrong current password" and "the
server is down" no longer read alike. `AuthProvider.resetPassword`/`deleteAccount` stopped
re-wrapping failures as `Exception(text)` — that wrap destroyed the status.

## Key files

- `frontend/lib/services/api_exception.dart` (new), `frontend/lib/services/api_service.dart`
- `frontend/lib/providers/auth_provider.dart` (enum, `classifyAuthFailure`, register/`_signIn`)
- `frontend/lib/l10n/auth_status_text.dart` (new, exhaustive switch — a new code cannot compile
  unlocalized), `app_en.arb` / `app_pl.arb` (+10 strings each)
- `frontend/lib/screens/auth_screen.dart`, `frontend/lib/widgets/auth_form.dart`,
  `frontend/lib/screens/settings_screen.dart`
- `frontend/test/providers/auth_registration_outcome_test.dart` (new, 11 tests),
  `frontend/test/screens/auth_screen_theme_test.dart` (the enum↔string pin, extended)

## Verification

- **Live, against a real backend** (local `docker compose` stack + `flutter run -d web-server`,
  headless Chromium, 480×900), five runs: register tab shows both rule lines; a fresh
  registration lands DIRECTLY in the Chats shell (no sign-in step); **pressing "Utwórz konto"
  again with the SAME name and password — the friend's exact situation — lands in the shell too,
  with no message at all**; the same name with a DIFFERENT password → *"Ta nazwa użytkownika jest
  już zajęta. Jeśli to Ty założyłeś to konto, zaloguj się."* + *"Przejdź do logowania"* → login
  tab prefilled; a wrong password on the login tab → *"Nieprawidłowa nazwa użytkownika lub
  hasło."*; the right one → shell. Screenshot at each step.
- `flutter analyze --no-fatal-infos` clean; **`flutter test` 1779 / 10 skipped** on master
  (1768 + 11 new), count verifier re-run against the captured log; CLAUDE.md §3 updated.
- Version bumped `0.2.16 → 0.2.17` (frontend-only release; **not deployed** — owner's call).

## Post-review (two-axis review of `90f7056...HEAD` per `skill://code-review`)

Both axes ran as parallel `reviewer` subagents, each pinned to the `fireplace-0a` worktree and
asked to echo `git rev-parse HEAD` (both reported `6dfdb37`) — the sibling worktree shares one
`.git`, so a wrong cwd would have reviewed `feat/passcode-lock` instead.

- **Standards: no hard violations.** Three judgement-call smells recorded, none acted on: the
  username rule now lives in three places (client regex, ARB wording, server `RegisterDto`), so a
  rule change needs synchronized edits or the door lies; the 400-split still sniffs the English
  word "password" (`auth_provider.dart:103`) — the one prose dependency left, documented, and
  unreachable for login/credentialChange; the tab-jump mutation has two owners in
  `auth_screen.dart` differing by one line (whether the status is cleared).
- **Spec: one real finding, FIXED in this commit.** A wrong current password in Settings read
  *"Nieprawidłowa nazwa użytkownika lub hasło."* — those dialogs never ask for a username.
  `AuthStatusCode.wrongPassword` now takes `AuthAttempt.credentialChange` 401/403
  ("Nieprawidłowe hasło." / "Wrong password."); a test pins that the SAME `ApiException`
  classifies differently per door.
- **Spec's second finding was a FALSE POSITIVE:** it attributed the tab `Semantics(selected:)` +
  48 dp touch target and the `ElevatedButton` spinner-colour fix to this change. Both predate
  `90f7056`; `git diff 90f7056...HEAD` over those files matches neither line. Nothing reverted.
  Lesson: a review finding about "scope creep" is a claim about the DIFF — check it against the
  diff before acting.

## Notes for next session

- **Not deployed.** Frontend-only: `git pull ; .\deploy-web.ps1`, then
  `cd scripts/smoke && node post-deploy-smoke.mjs`. Backend needs nothing.
- Landed on `master` from the `feat/passcode-lock` worktree by patch transplant — the working copy
  at `Desktop/Fireplace` is checked out on that branch, `Desktop/fireplace-0a` holds `master`.
  **`git status -sb` first, every session; CLAUDE.md §1's claim that `Desktop/Fireplace` is on
  master is currently false.** `feat/passcode-lock` will need a rebase; the overlap is
  `settings_screen.dart` (additive rows) and the l10n files (unioned).
- Not done, deliberately: `/auth/register` is still not idempotent. The recovery affordance covers
  the user-visible half; an idempotency key (or a name-availability probe) is the server-side half
  and needs a wire decision.
- The register throttle is 10/h per IP and the login throttle 30/15 min; auto-sign-in adds ONE
  login per registration. The `test_e2e` harness registers through `ApiService` directly, so only
  `auth_token_fault_injection_test` pays it.
