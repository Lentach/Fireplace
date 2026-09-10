# 2026-09-09 — c9: the phrase at the door + the Czaty nudge (spec (lxxxiii), 0.2.34, web-only)

**Date:** 2026-09-09

Owner's words that opened the session: "i wont you to finish multidevice once for all", after three
yes/no answers — phrase at registration + legacy nudge **go**, fold the three review judgement calls
**yes**, the ~1 ms counter residual **record as accepted**. His product framing, verbatim in spirit:
*"PWA users never need to link. The phrase does not lock the account. For a plain PWA user the 12 words
mean exactly one thing: forgot password → still get in."*

## What was done

- **Spec first** (`docs/design/multi-device.md` §12): **(lxxxiii)** in three clauses, plus one sentence
  in (lxxxii) clause 2 recording the accepted residual (the dummy Argon2 paths skip the ~1 ms
  failure-counter UPDATE; below network jitter; recorded, not fixed).
- **Clause 1 — at registration.** `AuthProvider.register` stamps `_freshRegistration` on the two paths
  that end SIGNED IN with an account these credentials CREATED (clean 201; lost answer → probe sign-in).
  The taken-but-mine path is an EXISTING account and is NOT stamped (F42). `clearStatus()` clears it;
  `consumeFreshRegistration()` reads it once. `ConversationsScreen` consumes it in its post-frame wiring
  and pushes `RecoveryKeyScreen(deferrable: true)` when `EncryptionProvider.hasIdentityBackup` becomes an
  EXPLICIT `false` (listener; never unknown, never true — F39). The screen gained `deferrable` → a
  `Później` `TextButton` (`recovery-key-later`) under the generate button, popping `false`.
- **Clause 2 — the generate button waits for E2E.** `RecoveryKeyScreen` reads
  `context.watch<EncryptionProvider>().isE2EReady` and disables "Wygeneruj" until it is true
  (`exportIdentityForBackup` throws before `initialize()` ran; at the door the identity is minted seconds
  after the shell). Applies to every door (F41). The failure snackbar is now the context-neutral
  `recoveryKeySaveFailed` (a dead key until now); `recoveryKeyBackupFailed` ("łączenie nie zostało
  włączone") DELETED from both ARBs — wrong on two of four doors.
- **Clause 3 — the nudge.** `utils/backup_nudge.dart`: `shouldShowBackupNudge(hasIdentityBackup,
  dismissedAt, now)` + `kBackupNudgeSnooze` (7 days). `SettingsProvider.backupNudgeDismissedAt` /
  `loadBackupNudge(uid)` / `snoozeBackupNudge(uid, {now})`, prefs `backup_nudge_dismissed_at_<uid>`
  (epoch ms, per account per install). `widgets/backup_nudge_line.dart` (`backup-nudge`,
  `backup-nudge-dismiss`): shield glyph + "Zabezpiecz konto — utwórz 12 słów" + X, muted tokens as
  `PeerIdentityChangedNote`. Rendered ABOVE the list in both layouts (mobile: the list stops scrolling
  behind the header while the line is up; desktop: between header and list) so it exists in skeleton /
  empty / populated states. "Później", the back arrow and the X all snooze; a saved backup removes it
  (`onRecoveryKeySet` flips the flag).
- **Copy:** `recoveryKeyBackupExplainer` PL/EN now says "odzyskuje hasło i konto" / "recover your
  password and the account"; `recoveryKeySubtitle` (Settings row) "Odzyskasz hasło i konto, gdy stracisz
  urządzenie" / "Recover your password and account if you lose a device". New keys
  `recoveryKeyLaterAction`, `backupNudgeTitle`.
- **Review folds (0.2.33 two-axis review, owner "yes"):** `_preLinkDivider(context)` extracted in
  `chat_detail_screen.dart` (both pill sites, one key); `AuthForm.onSubmit(username, password)` +
  REQUIRED `onRecover(username, phrase, newPassword)` — the `phrase!` bang in `auth_screen.dart` is gone
  (the recover arm of the mode switch is an honest no-op comment); a test that appends to the loaded
  list IN PLACE while a filtered view is cached and asserts the view refreshes (F43).
- **Test harness fixes the change forced:** `recovery_key_screen_test.dart` now calls
  `markE2EInitialized()` (the real flow reaches the screen initialised); `settings_screen_version_footer_test`
  pinned `textContaining('dev')` — the new subtitle contains "device", so it now pins `'· dev'`.
- `frontend/CLAUDE.md` §5 gained the (lxxxiii) bullet. Root §3 counts updated (see Verification).

## Key files

`docs/design/multi-device.md` (lxxxii residual, lxxxiii), `frontend/lib/providers/auth_provider.dart`,
`frontend/lib/providers/settings_provider.dart`, `frontend/lib/screens/conversations_screen.dart`,
`frontend/lib/screens/recovery_key_screen.dart`, `frontend/lib/screens/auth_screen.dart`,
`frontend/lib/screens/chat_detail_screen.dart`, `frontend/lib/widgets/auth_form.dart`,
`frontend/lib/widgets/backup_nudge_line.dart` (new), `frontend/lib/utils/backup_nudge.dart` (new),
`frontend/lib/l10n/app_{pl,en}.arb` + generated, `frontend/test/screens/conversations_backup_nudge_test.dart`
(new), `frontend/test/screens/recovery_key_screen_test.dart`,
`frontend/test/providers/auth_registration_outcome_test.dart`,
`frontend/test/providers/messaging_provider_envelope_status_test.dart`, `frontend/CLAUDE.md`, `CLAUDE.md`.

## Verification

- **Mutants, 1 substitution each, printed, killed, restored byte-identical (runner deleted, `git status`
  clean of it):** F39 offer fires on `true` → nudge test "WITH a backup is never offered"; F40 predicate
  ignores `dismissedAt` → "snooze hides it for exactly seven days"; F41 generate ignores `isE2EReady` →
  "disabled until E2E is ready"; F42 taken-but-mine stamps freshness → "a taken name that opens with
  these credentials"; F43 `_visibleMessages = null` dropped from `notifyListeners` → "rebuilt after an
  IN-PLACE mutation". The Grep/`str.count` matcher must be CRLF-aware — F42 first reported 0 occurrences
  on the CRLF `auth_provider.dart`.
- **Backend untouched** (`git diff --stat -- backend/` empty) → web-only release; ratchet PASS at 898.
- **Full Flutter suite:** see the LATEST entry for the final count (the first full run had exactly one
  red: the footer test's `'dev'` substring, fixed as above).
- **Live, on a rebuilt bundle against the local stack (three fresh accounts, ids 207–209):**
  register `c9nudge3` → shell → **offer within 1 s of the status** (durable probes, since removed, read
  `TMP_CONV_FRESH {fresh:true, flag:null}` → `TMP_CHECK {flag:false}` → `TMP_OPEN`) → Wygeneruj → 12
  words → Zapisałem → word nr 2 → saved → Czaty with NO line; Postgres: `recovery_keys` backup row 1,
  `account_authorizations` 0 (**the phrase did not enrol**); `POST /auth/recover` with those 12 words →
  201; login with the new password 201, old password 401 — the whole PWA-user value proposition end to
  end. `c9nudge2`: offer → Później → line gone; snooze key removed via devtools + reload → line back on
  the Grafit theme (muted line reads fine on dark), **no re-offer after reload** (the stamp is consumed);
  tap the line → the same screen WITHOUT Później; back; X → line gone. `c9nudge` (run 1): the offer
  appeared, but my 26 s screenshot caught the Czaty line with the offer not yet painted — that run had a
  26 s login→socket gap on a cold profile and the server-side sequence only shows one login; the two
  probed runs are deterministic, so recorded as an observation, not a defect.
- **Not iOS-verified** (no device on this box): the offer's route over a PWA shell on iPhone.

## Notes for next session

- The multi-device programme has no open owner asks left. Standing "queued, not started": `/.well-known/
  assetlinks.json` (waits for the APK); the dead `fireplace-0a` worktree (do NOT delete unasked); the
  change-password dialog iOS viewport pin (owner never answered).
- **Owner still has no phrase on `bob208#9939` (id 37)** — now the Czaty line will tell him every 7 days
  until he does. Keep saying it anyway.
- A route pushed from a provider listener over the shell is popped by the AuthGate's `gated` transition
  (spec (lxxiii) clause 3 popUntil) — the offer then counts as "later" (7-day snooze). Rare on a fresh
  account (only `identityCheckUnavailable`); accepted, not special-cased.
- Drive technique held: app-mode Chrome per profile on `--remote-debugging-port`, pixel clicks, CDP
  `Input.insertText`; a cold profile needs ~15 s before the first form paints — clicks before that land
  on nothing (run 3's first attempt). `?q=` classification of screenshot frames is a cheap way to find
  WHEN a route appeared.

---

## Addendum — 0.2.35, (lxxxiii) clause 4: the line asked for a BLOB, not a PHRASE (both tiers)

**Field report, hours after 0.2.34 went live:** user `goonboy` (id 48) "already had his phrase from
earlier" — the Czaty line told him to secure the account, the door showed twelve NEW words unlike
the ones on his paper. Prod row: phrase created 2026-09-02 (pre-(lxxviii)), `backupBlob` NULL,
`createdAt` unchanged → he had NOT confirmed (`setRecoveryKey` rewrites `createdAt`), so his paper
phrase was still the valid one. Told the owner: back arrow, keep the old paper, X the line.

**Root cause:** the line and the offer keyed off `hasIdentityBackup` (a sealed blob exists — only
phrases created since 0.2.23 have one). For a PWA user the phrase means password recovery, and a
verifier-only phrase already does that at `/auth/recover`. Prod: 2 verifier-only rows, 0 blobs — the
line nagged exactly the two people who had already done the right thing. Second defect: the screen
never said that new words REPLACE an enrolled phrase.

**Fix (owner "Go, both tiers"):** `IdentityResetService.hasRecoveryPhrase(userId)` (any
`recovery_keys` row) rides `ownKeyBundleStatus` as an additive explicit bool next to
`hasIdentityBackup`; `EncryptionProvider.hasRecoveryPhrase` (absent = UNKNOWN); the Chats line and
the door offer key off it; `onRecoveryKeySet` success flips both; **both flags reset to `null` in
`clearAll()`** (they never did — user A's answer would have painted user B's list until B's first
status). The devices-screen nudge keeps `hasIdentityBackup` (an enrolled primary needs the blob).
`RecoveryKeyScreen` renders `recoveryKeyReplacesExisting` in the error colour above the generate
button whenever `hasRecoveryPhrase == true`: "Masz już frazę. Nowe słowa ją zastąpią — stare
przestaną działać." / "You already have a phrase. New words replace it — the old ones stop working."

**Proof:** F44 (line keys off `hasIdentityBackup`), F44b (offer likewise), F45 (client reads an
absent field as false), F45b (server drops the field) — 1 substitution each, printed, killed,
restored. Backend 1119/62, Flutter 2094/14, ratchet 898 PASS. Live on the local stack with
`c9nudge3` made verifier-only by SQL (goonboy's shape): Czaty shows NO line, Settings → Klucz
odzyskiwania shows the red replace warning above the button; control `c9nudge2` (no row) still gets
the line. Deploy order backend FIRST — a 0.2.35 client on a 0.2.33 server reads the missing field as
UNKNOWN and shows nothing, the safe direction.

**Traps:** Docker Desktop died mid-session (`npipe` gone) — restart it and wait ~2.5 min for the dev
backend; `npm test` rewrote `backend/package-lock.json` (48 `libc` lines, npm-version noise) —
reverted, not committed; `backend/test-output.txt` is now gitignored like the frontend one.

---

## Addendum — 0.2.36: the link scanner is a full-screen surface (web-only)

**Owner's nit, with an iPhone screenshot:** in scan mode the camera was a 280 px tile under the QR
and the code box — "looks like 2005 tec". Reference scanners (Signal iOS, WhatsApp, Telegram —
[support.signal.org](https://support.signal.org/hc/en-us/articles/360007320551-Linked-Devices),
[umnico Telegram guide](https://umnico.com/blog/telegram-web/), [WhatsApp Web guide](https://timelines.ai/whatsapp-web-qr-codes))
all converge: camera fills the viewport, dark scrim with a square window and bracket corners, one
caption, an X, the typed fallback at the bottom, and the hit hands over immediately.

**Built:** `screens/link_scan_screen.dart` — `LinkScanScreen` pushed with `fullscreenDialog: true`
from both ceremony screens; pops a sealed `LinkScanResult` (`LinkScanCode` / `LinkScanUnsupported` /
`LinkScanManual` / null for X) exactly once (post-frame pop behind a `_popped` latch — the native
`errorBuilder` fires during build). `Stack(fit: expand)`: `LinkQrScanner` fills; `IgnorePointer(CustomPaint)`
scrim with a 0.68×shortest-side rounded window and four bracket arcs in `colorScheme.primary`; X and
the caption+manual column are `PointerInterceptor` children (the web `<video>` is a platform view).
The `_scanning` state, `link-scan-cancel` button and the 280 px `SizedBox` are gone from both
screens; `scannerBuilder` is handed through so the existing tests stay camera-free. No torch (the
facade has no seam; untestable here). No new strings.

**Proof:** `link_scan_screen_test.dart` (4: the four exits + two callbacks in one frame pop ONCE);
`link_scanner_screens_test.dart` re-pointed at the route (bounded pumps after a hit — the ceremony's
waiting step animates, `pumpAndSettle` never returns). Flutter **2098/14**. Live on a rebuilt bundle in
app-mode Chrome with `--use-fake-device-for-media-stream`: gate → Zeskanuj → full-screen scanner
(screenshot 08: black, scrim, brackets, caption, X, manual), DOM `<video>` 464×805 = viewport,
`readyState 4`, playing; X → page restored (tracks stopped, `srcObject` null — the detached host element stays in the DOM); manual → the typed field; and a synthesized
camera frame (the page's own n-code QR pasted into a `canvas.captureStream()`) → decoded → route
popped → `_submitCode` → the controller's refusal "Nieprawidłowy kod…" on the page — the whole
path through the route. **iPhone-verified by the owner on prod 0.2.36** ("full screen camera works"); he also linked a desktop from the phone the day before. Android untested (no device).

**Traps:** an occluded app-mode Chrome window is `visibilityState: hidden` → Flutter stops ticking →
a CDP screenshot shows the Zoom page transition frozen at 99 % (previous route bleeding through);
`page.bringToFront()` does not un-occlude. The second scanner open needs ~4 s before its controls
answer (camera re-acquire) — a 1.5 s wait read as "manual button dead". `docker compose up` on the
bind-mounted backend rewrites `backend/package-lock.json` (48 `libc` lines) — revert every time.

**Provenance note:** the 0.2.36 deploy-state commit `e292aee` was made with `git add .cursor/session-summaries`
and swept in a PARALLEL session's finished work — the 2026-09-10 "Workflow 2.0" LATEST entry, its Dependabot
rotation banner, and `2026-09-10-session-workflow-2.0.md`. Nothing of theirs was lost or altered; it just rides
under my message. Left in place on purpose (rewriting master or deleting another session's evidence is worse).
`docs/agents/workflow-2.0.md` is theirs and untracked. Lesson: `git add` named files, never the directory.
