# 2026-08-19 — composer attachment/keyboard regression: what is PROVEN, what was deleted, where to start

Second half of 2026-08-19 (first half: `2026-08-19-session-anchor-revert.md`). This
session produced **no shipped code**. Everything it built was deleted at the owner's
instruction after two failed attempts made him lose confidence. What survives is
evidence, and it is worth more than the code was.

**Read this before touching the composer, the attachment picker, or the video batch.**

---

## 1. Owner state — read first

The owner is out of patience with this area, for good reason: three releases in a row
touched the attachment picker and the bug is still there, plus new ones. His words:
*"you seems to doesnt understand and keep regressing"*, and *"we made huge regress on
composer and now all old bugs are back"*.

Standing consequences:

- **Ship NOTHING in this area without a green repro run + his explicit OK.** No
  exceptions, no "it's tiny".
- **Do not use him as the test loop.** Section 4 gives a repro that needs no phone.
  Exhaust it before asking him for anything.
- He asked for the whole session's work to be deleted. It was. Do not resurrect it
  from git history "because it was nearly working" — it was not.

## 2. The bug, stated precisely

Two distinct symptoms, repeatedly conflated during the session. Keep them apart:

**Symptom K (ours).** Tap paperclip → dismiss the picker → tap the composer → the
keyboard **flashes up and straight back down** (iOS) or **never rises at all**
(Android). A normal composer tap with no prior paperclip works fine. Later in the day
the owner also saw the composer **jump to the top of the screen** with the chat gone.

**Symptom P (Safari's).** With the keyboard UP, tapping a file input makes iOS draw its
Photo Library / Take Photo or Video / Choose File menu **mid-screen** instead of at the
control, and the keyboard collapses as it opens (returning on cancel).

## 3. What is PROVEN — do not re-derive

Every line here was measured on a device or an emulator this session.

1. **Symptom K reproduces on clean 0.1.17**, i.e. code with none of this session's
   changes and with #145 already reverted:
   ```
   fresh load      : 148ms:down -> 750ms:UP    keyboard rises, stays
   after paperclip : 98ms:down                 keyboard never rises
   ```
   ⇒ **It is NOT caused by anything shipped on 08-18/08-19.** It predates them.

2. **It is NOT the accept list.** On the owner's iPhone, a probe row using the exact
   *pre-video* list (`.jpg,.jpeg,.png,.gif,.pdf,.doc,.docx,.xls,.xlsx,.txt,.csv`)
   misplaced the menu identically to today's list. The earlier "video extensions are
   the regression" theory (written in the previous summary) is **DEAD — ignore it.**
   Video extensions only change iOS's wording ("Take Photo" → "Take Photo or Video").

3. **It is NOT `file_picker`.** A throwaway Flutter web app — one `TextField`, one
   `FilePicker.pickFiles()` — did **not** reproduce Symptom K on Android, with the
   chooser genuinely opening (screenshot-verified). ⇒ the fault is in **our composer**.

4. **Symptom P is Safari's, not ours.** A bare static HTML page (no Flutter, no
   `file_picker`, no viewport pin) reproduces it fully on the owner's iPhone:
   ```
   A TAP KEYBOARD_UP   vh=362   → menu mid-screen
   A TAP keyboard_down vh=699   → menu AT the button
   A CANCEL KEYBOARD_UP         → keyboard returns  (this is the "flash" half)
   ```
   ⇒ **keyboard up = menu centred; keyboard down = menu anchored.** Nothing in our code
   participates. Chasing placement in Dart is wasted effort.

5. **A deferred `.click()` after `blur()` is silently BLOCKED by Safari.** 11 taps
   produced zero menus and zero `cancel`/`change` events. Any fix shaped
   "blur → wait → open" cannot work on iOS. The same-gesture variant
   ("blur + open in one turn") was built but **never tested** — that is the one open
   experiment.

6. **`0cbf17b` ("video messages + UX batch") is NOT just video.** 60 files,
   +3133/−524, and it also carries:
   - the **0.1.10 identity guard + boot markers** (the silent key-churn fix),
   - the **`PeerIdentityChangedBanner` removal** (owner ruling: never resurrect),
   - the anti-quantum note reveal sheet, `instant_opaque_route` fade, PL theme names,
     snackbar theming.

   ⚠️ **`git revert 0cbf17b` would resurrect the banner and undo the identity guard.**
   Never plain-revert it. Any rollback here must be surgical, file by file.

## 4. The repro — one minute, no phone

This is the single most valuable artifact of the session. Android's own IME state is the
oracle, so the keyboard is *measured*, never eyeballed.

```bash
# 1. emulator
"$ANDROID_SDK/emulator/emulator.exe" -avd Pixel_7 -no-snapshot-load -no-boot-anim

# 2. serve a web build + backend, reverse both so localhost = secure context
adb reverse tcp:8091 tcp:8091 && adb reverse tcp:3000 tcp:3000
adb shell am start -a android.intent.action.VIEW -d http://localhost:8091

# 3. keyboard oracle (4 KB dump; the 580 KB `dumpsys input_method` is too slow to poll)
adb shell dumpsys window InputMethod | grep isVisible     # isVisible=true => keyboard up
```

Sequence: open a chat → tap composer (**expect UP**) → open the action panel → tap the
paperclip → dismiss the chooser → tap the composer again (**bug: stays down**).

Backend + accounts for it: `docker compose -p <name> up`, then register/friend two users
**inside the container** (the register throttle is 10/hr/IP) and seed the pair directly:
```sql
insert into friend_requests (status, sender_id, receiver_id, "respondedAt") values ('accepted',3,4,now());
insert into conversations (user_one_id, user_two_id) values (3,4);
```
Register wants `{username,password}`; login wants `{identifier,password}` and returns
`access_token`. `AppConfig.baseUrl` auto-detects `http://<host>:3000`, so a plain
`flutter build web` served on `localhost:8091` needs no dart-define.

## 5. Leading suspects for Symptom K — untested, in priority order

1. **The keyboard-dismiss `Transform.translate` in `chat_composer_viewport.dart`**,
   added by `0cbf17b`. A paint-only ease that moves the composer away from its layout
   position on keyboard-hide. It is in the documented **motion-BANNED zone**, it is an
   owner-approved exception whose **device A/B was never performed** (still owed since
   0.1.11), and "composer painted where it should not be" is exactly the owner's
   top-of-screen screenshot. Smallest useful experiment: delete the dismiss-slide and
   the emoji-panel slide, then run §4.
2. **Stale focus state.** `_requestComposerFocus` (`chat_input_bar.dart:240`) is guarded
   by `if (!_focusNode.hasFocus)`. If Flutter still believes the composer is focused
   after the file dialog took DOM focus, `requestFocus()` never fires and the engine
   never reattaches its hidden input. This *predicts both surfaces*: Android gets no
   keyboard, while iOS additionally calls `TextInput.show` via
   `showSoftKeyboardIfHidden` (`soft_keyboard_web.dart:10`, **iOS-WebKit-only**) — a
   keyboard that appears and immediately dies, i.e. the flash. **Unverified.** Confirm
   by reading `document.activeElement` mid-bug over CDP (§7).
3. The iOS viewport pin (`web_ios_viewport_pin_web.dart`, `position:fixed` on `<body>`
   / `<flutter-view>` while focused). Shipped in **0.0.68**, long before the good state,
   so it is not the trigger on its own — but it may be the mechanism something else now
   trips.

## 6. Android picker — owner ruling, nothing shipped

On Android the paperclip currently opens the OS chooser, which lists the **camera twice**
(`aparat / aparat / plik`) because the accept list carries both `image/*` and `video/*`;
Android splits that into stills-camera and video-camera, and offers no gallery door.

Owner's ruling: **Android does not need to look like iOS** — but it must offer
**image / camera / file**, three unambiguous doors.

An in-app three-row sheet doing exactly that was built and verified on the emulator
(the camera row was DOM-proven to create `accept="image/*,video/*" capture="environment"`),
then **deleted with the rest of the session's work**. Two rejected shapes, do not repeat
them: a `CupertinoActionSheet` (wrong control — full width, light, blue, icon-right,
Cancel button) and a hand-built dark iOS UIMenu clone (owner: Android may look like
itself). If rebuilt: app glass sheet, rows image/camera/file.
⚠️ Unverified even in the deleted version: whether the *photo-library* row's
image+video accept re-opens the duplicated-camera chooser one level down.

## 7. Tooling notes that cost time

- **CDP into the emulator's Chrome** is available and useful:
  `adb forward tcp:9222 localabstract:chrome_devtools_remote`, then
  `http://127.0.0.1:9222/json`. The websocket handshake **needs
  `suppress_origin=True`**, else 403.
- To catch inputs `file_picker` creates and removes, install a `MutationObserver` on
  `documentElement` *before* the tap — a post-hoc `querySelectorAll` finds nothing.
- Emulator tap coordinates **shift when the keyboard is up**; screenshot first and
  re-measure, or taps silently land on the keyboard (this produced one false
  "no repro" that had to be thrown away).
- `adb.exe` is not resolvable from the bash tool on this box — drive it from a Python
  `subprocess`. `exec-out screencap -p` must also be captured in Python; shell
  redirection corrupts it to 2 bytes.
- The Python kernel hangs on `subprocess` calls with large output — write a `.py` file
  and run it via bash instead.
- **Probe watchdog bug, do not repeat:** a shared no-show timer was cleared by each new
  tap, so 11 blocked clicks reported nothing and the owner's keyboard ended up jammed
  on a static page. Make watchdogs per-tap, and always give a probe an explicit
  "nothing opened" signal.

## 8. What was deleted, what remains

**Deleted:** branch `feat/android-attachment-sheet` (never pushed), all worktrees
(`fp-emu`, `fp-revert`, `fp-ci`, `fp-anchor`), the LAN/prod probe pages, the throwaway
repro app, helper scripts, the `fireplace-emu` docker stack **with its volumes** and its
test accounts, the emulator, and `~/fireplace/frontend-build/probe` on the VM
(verified gone). The parallel session's `fireplace-0a` stack and worktree were not
touched.

**Remains on master:** `356f3fa` (the #145 revert + 0.1.17 bump — removing it would put
the broken anchor back), `4b7c807` (CI skips prose-only commits), and the session
summaries. Production: **0.1.17 / `356f3fa`**, `/health` ok, picker code byte-identical
to 0.1.15.

## 9. Where the next session should start

1. Read §3 and do not re-litigate any of it.
2. Stand up §4. Confirm the repro goes red before changing anything.
3. Test suspect 1 (delete the two motion exceptions) → run §4. If green, that is the
   fix; show the owner before/after numbers, then ask.
4. If red, test suspect 2 with CDP `document.activeElement` and fix the focus guard.
5. Only after §4 is green, ask the owner whether he still wants the Android
   image/camera/file sheet (§6) — as a separate change, separately approved.
6. Placement (Symptom P) is Safari's. The ONLY untested idea is same-gesture
   blur+open (§3.5). If it fails, tell the owner honestly that iOS decides this.
