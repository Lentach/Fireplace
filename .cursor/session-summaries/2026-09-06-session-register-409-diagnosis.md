# Session — "friend cannot register": three 409s he could not read, then a 201 he never saw

**Date:** 2026-09-06 (investigation only, no code changed)

## What was done

Owner reported a friend could not register; screenshot: iPhone (iOS 18.7 WebKit), `REJESTRACJA`
tab, username `ma0i`, red `Coś poszło nie tak. Spróbuj ponownie.`, footer commit `c8f662e` (the
then-live 0.2.15 bundle — pre-deploy session, NOT a stale-build bug).

**Two findings, in order. The first explains the attempts, the second explains why he still has
no working account: the account WAS created and the client reported failure anyway.**

Evidence, from prod (`ubuntu@51.68.138.13`), all times UTC (Warsaw = UTC+2):

- nginx `access.log`, `95.65.0.220` (home WiFi, Orange PL): `POST /auth/register` at
  `21:05:17`, `21:05:22`, `21:06:19` → **409, 409, 409** (75-byte body =
  `nickname is already taken`). DB `chatdb`: **`maoi` = user id 60, created 2026-05-17** — that
  is the collision. He saw only "Coś poszło nie tak".
- Then `46.113.6.13` (cellular) at `22:01:54` → **201**, creating **user 114 `ma0i#5269`**.
  **Same browser, one session** — counted, not eyeballed: `95.65.0.220` = 27 requests, 27 match
  `Brave`, 0 match `Telegram`, **1 distinct UA**; `46.113.6.13` = 1 request, 1 `Brave`, 0
  `Telegram`, 1 distinct UA — and the two UA strings are identical (`sort -u` over both IPs
  yields one line). **My first report's "Telegram in-app WebView" label was wrong**: the Telegram
  chrome in the screenshot is the owner's own image viewer; the friend's browser was Brave on iOS
  18.7. The IP flip lands on exactly that one POST — a WiFi→cellular handoff mid-request, the
  failure mode the timeout comment at `api_service.dart:28-38` was written for.
- **The account was never used**: `grep -c auth/login` over both IPs = **0**, `key_bundles` for
  user 114 = **0**, `refresh_tokens` = **0**, no `devices` row. A user who saw the green
  "account created, now log in" would have logged in; he did not.
- The tab kept running past the 201 (asset 304s at 22:07:07 and 22:12:45, no `GET /` reload), so
  nothing reset the UI. No `499` on that request (the only two today are 14:24 media fetches), no
  nginx upstream error, otherwise near-idle traffic. The backend image finished building at
  22:11:49; its START time is unknown, so build CPU contention at 22:01:54 can neither be shown
  nor excluded. The access log is bare `combined` — **no `$request_time`**, so server latency for
  that request is unrecoverable, and a Dart `Future.timeout` never aborts the socket, so nginx
  logs the 201 under either hypothesis. **Server data cannot separate them; stop mining logs.**
- **Therefore the screenshot cannot be a processed success.** On a 201 the screen sets
  `registerSucceeded` and switches to LOGOWANIE (`auth_screen.dart:183-185`), and switching tabs
  back calls `clearStatus()` — so a red error under the REJESTRACJA tab means the 201 was NEVER
  processed by the client. Remaining possibilities, indistinguishable from server-side data:
  the response was lost on the network handoff, or it outran `_kAuthTimeout` (15 s,
  `api_service.dart:39`). Both surface as `unexpectedError`. The alternative reading — the
  screenshot was taken in the ~6 s before the submit with the 21:06 banner still up — stays
  possible (it is one continuous Brave session, so a stale banner CAN survive to that moment) but
  is no longer the published conclusion. **The one cheap disambiguator left is the friend: did
  the last tap spin for ~15 s before the red text appeared?**
- **Actionable for the owner right now: tell him to LOG IN as `ma0i` with the password he
  typed.** Registering again returns 409 → the same unreadable message → a permanent dead end.

## The client bugs behind the "cannot register" report

1. **Every non-network failure collapses into one useless string.**
   `ApiService.register` (`frontend/lib/services/api_service.dart:97`) throws
   `_errorMessage(response, 'Registration failed')`, which already contains the server's
   `message` (`nickname is already taken`). `AuthProvider.register`
   (`frontend/lib/providers/auth_provider.dart:515-528`) discards it: `_networkErrorCode`
   (`:553-563`) returns `serverUnreachable` for a fetch/socket failure and
   **`unexpectedError` for everything else** — 409 taken, 400 DTO validation, 429 throttle
   (`/auth/register` is 10/h per IP, `auth.controller.ts:14`), 502 mid-deploy. All render as
   `authStatusUnexpectedError` = "Coś poszło nie tak. Spróbuj ponownie."
   (`auth_screen.dart:33`). There is NO `409` / taken-nickname handling anywhere in
   `frontend/lib` — grepped.
2. **The status is cleared only on a tab switch** (`auth_screen.dart:158,166`). Editing a field
   or submitting again does not clear it, so an old failure keeps sitting under the form and
   describes a request that is no longer the one the user is looking at.
3. **`serverUnreachable` cannot fire on a non-Chromium engine.** `_networkErrorCode` matches the
   substrings `Failed to fetch` / `Connection refused` / `Connection reset` / `SocketException` /
   `NetworkException`. Read at source, `http 1.6.0` (`pubspec.lock`), file
   `http-1.6.0/lib/src/browser_client.dart:148-160`:

   ```dart
   Object _toClientException(Object e, BaseRequest request) {
     if (e case DOMException(name: 'AbortError')) {
       return RequestAbortedException(request.url);
     }
     if (e is! ClientException) {
       var message = e.toString();
       if (message.startsWith('TypeError: ')) {
         message = message.substring('TypeError: '.length);
       }
       e = ClientException(message, request.url);
     }
     return e;
   }
   ```

   So the message is the ENGINE's `TypeError` text with the prefix stripped. **The package holds
   no `Failed to fetch` literal anywhere** — its only hardcoded message on this path is
   `Invalid content-length header [$contentLengthHeader].` (`:107-110`). That means the app's
   match list bets on Chromium's exact wording; a `TimeoutException after 0:00:15.000000` matches
   nothing at all. On any engine that words it differently the transport failure lands in
   `unexpectedError`. **iOS WebKit is believed to say "Load failed" / "The network connection was
   lost" — [INFERENCE, platform knowledge; there is no iOS device here and no captured client
   log from the friend's session to confirm it].** The mechanism (engine-supplied text, no
   library constant) is verified; the specific WebKit string is not.
4. **A lost register response leaves an orphan account with no path back.** `POST /auth/register`
   is not idempotent and the client has no reconciliation: the row is committed, the user is told
   it failed, and every retry of the same name is a 409 rendered as the same generic sentence.
   `Future.timeout` explicitly cannot abort the in-flight request (`api_service.dart:36-38`), so
   the 15 s budget converts a slow success into exactly this state.

Contributing: client-side username validation is **non-empty only**
(`frontend/lib/widgets/auth_form.dart:71-73`), while `RegisterDto` demands 3–20 chars and
`^[a-zA-Z0-9_]+$` — so a 2-char or accented nickname also comes back as the same generic
string. Password strength IS validated client-side (`:29-34`, mirrors `PASSWORD_REGEX`), so
that was never the friend's problem.

Design note, not a bug: `users.create` refuses a duplicate username outright
(`backend/src/users/users.service.ts:44-48`) even though every account carries a 4-digit `tag`
whose whole purpose is disambiguation (`maoi#3049` vs a hypothetical `maoi#5269`). Discord-style
"same name, different tag" is a product decision the owner can take; today the tag only
prevents collisions the username check has already made impossible.

## Key files

- `frontend/lib/providers/auth_provider.dart:515-563` — where the reason dies.
- `frontend/lib/services/api_service.dart:63-101` — where the reason still exists.
- `frontend/lib/screens/auth_screen.dart:24-36,156-188` — status mapping + clear-on-tab-only.
- `frontend/lib/widgets/auth_form.dart:29-34,71-73` — password validated, username not.
- `backend/src/users/users.service.ts:44-62`, `backend/src/auth/dto/register.dto.ts`,
  `backend/src/auth/auth.controller.ts:12-18` — 409/400/429 sources.

## Verification

Read-only. Prod nginx access log + `chatdb` rows are the proof; nothing was deployed, nothing was
changed. **The code read IS the code that ran**: `git diff c8f662e..HEAD --` over
`auth_provider.dart`, `auth_screen.dart`, `api_service.dart` and `auth_form.dart` is EMPTY, so the
working tree matches the bundle in his footer. Incidental re-verification (volatile facts, §1):
prod is **frontend `0.2.16 / fda92b3`** (`curl …/version.json`) and **backend `0.2.4 / 9a1c4396`**
on `master` (container started 2026-09-05T22:12Z) — which is exactly what this file's LATEST
deploy-state block already said, so nothing there needed correcting. (An earlier draft of this
summary claimed it did; that draft was written in the `feat/passcode-lock` worktree, whose LATEST
copy still carried the pre-deploy `0.2.15 / c8f662e` block. Master's was current.) His attempts
predate that deploy, which is why his footer shows `c8f662e`.

## Notes for next session

Fix (not implemented, owner said investigate only), in defect order: (1) `AuthStatusCode` gains
`nicknameTaken` (409), `invalidInput` (400), `tooManyAttempts` (429) fed by the HTTP **status** —
`ApiService` must surface the status, not just a prose string — plus EN+PL strings; (2) clear the
status on submit and on field edit, not only on tab switch; (3) widen/replace the transport
classification so WebKit wordings and `TimeoutException` stop landing in `unexpectedError`
(matching on exception TYPE beats substring matching on messages); (4) **the 409 needs a RECOVERY
AFFORDANCE, not just a truthful string** — this is the trap that actually stranded him: after a
lost response on a committed 201, "nickname is already taken" sends the user to invent a
different name, the one action that guarantees he never finds the account he just made. The 409
copy must offer the jump ("this name exists — if you just created it, log in") and switch to
LOGOWANIE with the username prefilled; the stronger fix is an idempotency key on register or a
name-availability probe. A regression test per branch is justified: "the door explains the
refusal AND offers the way out" is observable contract, and this cost a real user four attempts,
an account he cannot reach, and a support ping.

Still unresolved and worth one question to the friend: whether the red banner was on screen
BEFORE he pressed create the last time (stale-banner path) or appeared as the answer to the
22:01:54 submit (lost-response path). Server data cannot separate them; his memory can.
