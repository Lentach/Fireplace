# 2026-08-19 — the popover anchor is REVERTED (0.1.17). Device data says why, and where to start next time.

Continues `2026-08-18-session-actions-billing-and-0.1.16.md`. 0.1.16's anchor fix
was wrong on both counts: it did not move the iOS popover, and it broke composer
focus. Owner called the revert. Shipped as **0.1.17 / `356f3fa`**, PR #148.

---

## 1. What the owner actually saw on 0.1.16

1. Tapping the paperclip still dismissed the keyboard, and the Photo Library /
   Take Photo or Video / Choose File popover still appeared **mid/top of screen**,
   not at the tile. The fix's entire purpose, unachieved.
2. **NEW regression:** after tapping the paperclip, tapping the composer made the
   keyboard appear and **immediately drop again** ("it jumps"). Tapping the
   composer without a prior paperclip tap behaved normally.

## 2. The process failure that produced this — read this part

**0.1.16 shipped on evidence that could not possibly have validated it.** The
proof quoted at merge time ("input at `left:216 top:788 40×40`, leftover inputs: 0")
measures where a DOM element sits. The symptom is where **Safari** chooses to draw
its native popover, and whether the **keyboard** survives. Desktop Chrome has
neither a native popover nor a virtual keyboard, so that test was structurally
incapable of going red on this bug. It was also **inherited from the previous
session and re-quoted as if freshly run.**

Compounding it: the LAN probe technique that *can* answer these questions was
already invented, documented, and proven on this exact device — and was not used
before shipping. The owner became the test loop. That is backwards, and it cost
two releases.

**Rule going forward: a fix for a platform-specific UI behaviour is not verifiable
on desktop. Probe the real device BEFORE merging, or say plainly that it is
unverified and let the owner decide with that on the table.**

## 3. Device evidence, finally collected properly

Five variants side by side on one page, each beaconing `visualViewport` height so
keyboard collapse is **measured, not eyeballed** (`KEYBOARD_UP` = viewport shorter
than the tallest seen by >120 px). Owner's iPhone, real taps.

Serving trick worth keeping: **the LAN route was blocked by Windows Firewall**
(inbound rule needs elevation), so the page went to
`~/fireplace/frontend-build/probe/index.html` — inside the existing static root, so
**no nginx change at all** — and beacons went to `/log?...`, which 404s but is
recorded verbatim in `/var/log/nginx/access.log`. Read them back with
`sudo grep -ho 'GET /log?[^ ]*' /var/log/nginx/access.log`. The next deploy wipes
the file automatically (verified: `/probe/` now falls through to the SPA).

| variant | at TAP | +400 ms | +1200 ms |
|---|---|---|---|
| **1 — what shipped in #145** | `KEYBOARD_UP focus=body` — composer already **BLURred before the tap** | `keyboard_down` | `keyboard_down` |
| 2 — real tap on a real input | `KEYBOARD_UP focus=body` | `keyboard_down` | `keyboard_down` |
| 3 — real tap + `preventDefault` on pointerdown | `KEYBOARD_UP focus=msg` | **`KEYBOARD_UP focus=msg`** | `keyboard_down` |
| 4 — `<label for>` activation | `KEYBOARD_UP focus=body` | `keyboard_down` | `keyboard_down` |
| 5 — shipped + `preventDefault` + hit-testable input | `KEYBOARD_UP focus=msg` | **`KEYBOARD_UP focus=msg`** | `keyboard_down` |

**Findings:**
- The shipped variant **loses focus before the tap registers** (`focus=body`, and a
  `composer BLUR` beacon precedes the TAP). That focus loss is the mechanism of the
  regression in §1.2 — Flutter's text-editing host and the transient DOM input end
  up fighting over focus, so the next composer tap raises then drops the keyboard.
- `preventDefault` on `pointerdown`/`mousedown` (variants 3 and 5) **does** keep
  `focus=msg` and the keyboard alive at 400 ms. It is the right primitive.
- **Nothing kept the keyboard past ~1200 ms.** Once the native sheet takes over,
  iOS collapses it in every variant. Keeping the keyboard through the picker may
  simply not be possible on iOS Safari.
- Popover *placement* still has no measurement — it cannot be read from JS. Only a
  human eye or a screen recording can answer it, and that data was never captured.

## 4. What shipped (0.1.17, PR #148)

`git revert` of `6a35042`, then bump. Deletes `attachment_picker_stub.dart` and
`attachment_picker_web.dart`, restores `chat_action_tiles.dart`.

- **Picker sources are byte-identical to 0.1.15** — empty diff vs `318bdf3` for
  `chat_action_tiles.dart` and `lib/utils/`. No drift smuggled in by the revert.
- `flutter analyze` clean; full suite **1315 passed / 10 skipped**. The first run
  hit the documented `chat_input_bar_attachment_test.dart` "video-then-caption
  keeps the media-first ordering contract" flake; whole-suite rerun green. (Never
  re-run it with a file list — project rule.)
- CI **6/6** (now includes CodeQL, auto-enabled when the repo went public).
- Built `356f3fa`, Giphy key verified in the bundle **before** publish (1
  occurrence), `pickAttachmentFileAt` confirmed absent from the built JS, manual
  staged publish, **smoke 5/5**.

**Known and OPEN after this revert:** the iOS popover still opens mid-screen. We
are back to 0.1.15 behaviour, which is worse-looking but has no focus bug.

## 5. If someone attempts this again

Start from variant **3 or 5**, not from what #145 did. Concretely: preserve focus
with `preventDefault` on `pointerdown`, and make the input genuinely hit-testable
(no `z-index:-1` / `pointer-events:none` — those are the likely reason Safari
ignores the element's position and centres its popover).

But first, **prove the placement claim on a real device with a screen recording**,
because the whole 0.1.16 episode happened for want of that one artifact. And
consider that the honest answer may be "iOS Safari decides this and we cannot
control it" — in which case the correct move is to stop spending releases on it.

## 6. Still owed / unrelated open items

- Owner's device A/B of the two 0.1.11 composer-motion changes.
- Video length cap and video tile sizing — owner asked for a brainstorm, not code.
- `deploy-web.ps1` exit-21 silent publish halt (11 manual publishes now).
