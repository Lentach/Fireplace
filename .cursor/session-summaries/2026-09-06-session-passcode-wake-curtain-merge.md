# 2026-09-06 — Passcode Lock: the phone-test round (wake re-stamp, privacy curtain, picker exemptions, disable → Settings), the master-deploy collision, MERGE and release as 0.2.22

Owner's sequence: "deploy this before merging, I'll test it first" → four bug reports from real
phones → "all looks fine, gg" → "merge deploy do the book". Everything below was proven on the
Pixel_7 emulator against the real build before it went to his phones; his phones were the final
verdict each time.

## What was done

**Branch test deploys (web only; the branch touches 0 backend files):** 0.2.17 `5257418` → 0.2.18
`794c96a` → 0.2.19 `eee079a` → (master deploy collision) → 0.2.20 `e060595` → 0.2.21 `1f83baf` →
0.2.22 `ad1e895`. Every one: `deploy-web.ps1` from a detached worktree, `PUBLISHED_OK` then exit 1
from the dep-less gate as documented, smoke from the main checkout `--commit <sha>` 5/5, bundle
grepped for `Blokada kodem`.

**1. Screen-off wake came back unlocked (iOS + Android PWA, 1-minute setting).** First answer was
wrong and is retracted: "the browser sends no event on screen-off". A probe page on the emulator
logged `blur` + `visibilitychange:hidden` at screen-off and `visible` + `focus` at wake. The app's
listener IS wired to them. Reading the persisted `passcode_last_active_at` on both edges over CDP
showed the stamp after wake = the WAKE instant. Flutter web delivers `hidden → inactive → resumed`
on wake; `MainShell` treats `inactive` as a departure (correct on the way out, and on iOS it may be
the only signal) and `noteBackgrounded()` re-stamped. Fix: `_away` latch — stamp once per departure,
cleared by every foreground verdict and by a lock; the latch guards the STAMP only, the 0 s verdict
still runs on every signal (advisor refinement — a picker span that ends without a return could
otherwise never lock). Desktop Chromium never delivers the intermediate `inactive`, which is why
the earlier headless proof passed. Tests: wake path, false-positive direction (lock → unlock →
5 s absence stays unlocked), lock closes the departure, second signal at 0 s still locks. Mutation
verified — the first attempt's `sed` anchored on `$` no-op'd in this CRLF tree; re-done with a
grep-verified edit.

**2. Wake-lock was "chat → white → lock screen".** The chat is the browser re-showing the last
painted frame before any code runs; the white was OURS (`PasscodeGate` painted a bare
`ColoredBox` for `unknown`, and the reload's document is bare until Flutter's first frame). A
Flutter-side curtain (`curtained` flag → `PasscodeCurtain`) passed every unit test and FAILED the
phone: burst screenshots on wake still showed the chat first. Measured: a real screen-off leaves
81–397 ms between `blur` and hidden; a Flutter frame does not land in that window. Setting state
is not painting a frame. Shipped: a DOM `#fp-curtain` in `web/index.html` (theme background + hex
padlock in the theme accent), shown SYNCHRONOUSLY by the page's own blur/visibilitychange handler
while armed, and at boot when `localStorage.flutter.passcode_enabled === 'true'` (verified: at
boot `display:block` with `flutter-view` absent). Dart (`utils/privacy_curtain*.dart`, js_interop
to `window.__fpCurtain`) arms it while a passcode is enabled and LIFTS it from `PasscodeGate` in a
post-frame callback only after a frame that paints what replaces it; lifting before the return
verdict flashes the chat — pinned by a provider test that records every notification and refuses
"clear + unlocked" between curtain and lock (mutation-checked). The Flutter curtain stays as belt
and braces and paints OVER the app, never Offstage (a pending `<input type=file>` lives there).
Proof: keyguard → CURTAIN → lock screen → curtain (relaunch boot) → lock screen; before: chat →
curtain → lock → blank. Pixel classification AND a visual read of `x1` (the heuristic had misread
`w1` earlier — never trust it alone).

**3. Attach picker exemptions.** Curtain (both layers) and the foreground verdict skip the
`composerNativePickerActive` span, like the immediate lock already did; `PasscodeGate` rebuilds
on the flag through a `ValueListenableBuilder` so `armDomCurtain(false)` reaches JS before the
picker's blur. Pinned by a gate test driving the real signal (ends the span inside the test body —
its 3-minute self-cap timer trips the binding's pending-timer check otherwise).

**4. Turning the passcode off** now pops back to Settings on success; a cancelled/refused prompt
stays put. Widget test with a real navigator stack.

**5. Curtain accent map** in index.html had two wrong hand-copied hexes (dark, teal); pinned against
`RpgTheme.ephemeralAccent` in `web_document_background_test.dart` — anchored INSIDE the `accents`
object, because the keys collide with the bootstrap background map and a document-order regex
would pin the wrong hex.

**The master-deploy collision.** Another agent deployed master `a6a6be9` (auth-clarity) labelled
"0.2.17" — a version the passcode test build had already used — rolling live BACKWARDS from
0.2.19; passcode was not in master, so the owner "didn't see passlock". Recovered by rebasing the
branch onto their master (code byte-identical to a merge; their auth fixes kept), bumping to
0.2.20, and restoring their LATEST entry which `--theirs` had dropped. Risk flagged to the owner:
any phone with the passcode ON that opened `a6a6be9` may have read `fpwk1:` envelopes as garbage
(master had no unwrap code) — he reported no damage.

**Merge and release.** `feat/passcode-lock` `d446a9d` (29 commits) fast-forwarded to master;
PR #164 auto-closed MERGED. The served `ad1e895` is an ancestor of master with only a docs commit
after it, so prod already IS master — no rebuild (a rebuild would ship identical code under a new
hash for nothing). Backend: 0 files changed since the live `9a1c4396` — nothing to deploy. VM
checkout moved to `master`. `frontend/CLAUDE.md` §10 header → RELEASED, plus a new bullet on
departures/returns and the rollback rule; planning files closed.

## Key files

`frontend/lib/providers/passcode_provider.dart` (`_away`, `curtained`, picker exemptions),
`frontend/lib/widgets/passcode_gate.dart`, `frontend/lib/widgets/passcode_curtain.dart`,
`frontend/lib/utils/privacy_curtain{,_stub,_web}.dart`, `frontend/web/index.html` (`#fp-curtain`),
`frontend/lib/screens/passcode_lock_screen.dart` (`_disable`), tests under
`test/providers/passcode_provider_test.dart`, `test/widgets/passcode_gate_test.dart`,
`test/screens/passcode_lock_screen_test.dart`, `test/utils/web_document_background_test.dart`.

## Verification

Suite 1957 / 14 skipped, analyze clean, CI green on the branch (PR #164), smoke 5/5 on every
deploy, emulator proofs as above, owner's phones: "it works now just fine".

## Notes for next session

- The branch-test rule ("a master deploy must rebase onto `feat/passcode-lock`") is RETIRED —
  passcode is master. The version rule stays: PATCH always above what `/version.json` serves.
- Still open, recorded not fixed (owner's call): wall-clock throttle + cleartext attempt counter;
  non-extractable CryptoKey; `fpwk1:` binds no AAD; KEK zeroing "until GC"; Android-only — a manual
  padlock during a fullscreen clip with sound leaves audio playing behind the `Offstage` lock.
- Emulator recipe that worked: `KEYCODE_SLEEP` / `KEYCODE_WAKEUP` + `wm dismiss-keyguard`, CDP via
  `adb forward tcp:9333 localabstract:chrome_devtools_remote`, DDC dev build takes ~90 s to boot
  after a reload, first boot ANRs — wait on `/proc/loadavg`. Docker Desktop quit twice between
  runs; `Start-Process 'Docker Desktop.exe'`.
