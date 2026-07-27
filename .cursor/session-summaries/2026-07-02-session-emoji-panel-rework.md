# Emoji panel rework — Signal/Telegram behavioral parity (feat/emoji-reactions)

**Date:** 2026-07-02

## What was done

Reviewed commit `1056d03` ("Upgrade emoji reaction UX") on `feat/emoji-reactions` against the user's Telegram screenshot target. The panel *look* was already right (`emoji_picker_flutter` 4.4.0: search bar top → grid → category bar + backspace bottom, suggested-reaction row, keyboard/emoji toggle icon swap). Five behavioral defects vs Signal/Telegram standard were found and fixed (commit `ce0ee58`, pushed):

1. **Keyboard+panel stacking (critical):** tapping the text field with the panel open focused the field → keyboard opened on top of the still-mounted 320px picker. Fix: `_closeEmojiPickerOnFocusGain` FocusNode listener — any composer focus gain (field tap, reply/edit refocus) closes the panel; keyboard and panel are now mutually exclusive.
2. **System back:** popped the chat route with the panel open. Fix: `PopScope(canPop: !_showEmojiPicker)` wrapping `ChatInputBar.build` — first back closes the panel, second pops.
3. **Send while panel open:** `_send`/`_sendStaged`/edit-branch always refocused the composer post-frame → keyboard summoned, panel killed. Fix: `keepEmojiPanel` captured at send start; refocus + iOS `_sendJustFired` fast-restore arming skipped — panel stays open after send (Telegram parity).
4. **Recording:** mic start left the panel mounted under the recording bar. Fix: `_onRecordingStateChanged(true)` closes it; `setRecordingForTest` now routes through the real callback.
5. **Reaction sheet under keyboard:** context-menu "more emoji" sheet was `Positioned(bottom: 0)`; with the keyboard up (long-press doesn't unfocus; `onTapOutside` deliberately disabled) it rendered behind the keyboard. Fix: `bottom: MediaQuery.viewInsetsOf(ctx).bottom` — live-tracked, follows keyboard dismissal mid-overlay.

Version stays `0.0.77` (branch already carries the unreleased 0.0.76→0.0.77 bump; one bump per released version).

## Key files

- `frontend/lib/widgets/input/chat_input_bar.dart` — focus listener, PopScope, send gating, recording close
- `frontend/lib/widgets/message/message_context_menu_overlay.dart` — keyboard-inset-aware picker sheet
- `frontend/test/widgets/input/chat_input_bar_send_test.dart` — 4 new regressions (focus-gain close, back-button close-then-pop, send-keeps-panel, recording-close); `_pump` refactored to shared `_providerScope`
- `frontend/test/widgets/message/message_context_menu_overlay_test.dart` — sheet-above-keyboard regression incl. live inset drop mid-overlay

## Verification

- `flutter analyze --no-fatal-infos` — clean.
- `flutter test test/widgets/input/chat_input_bar_send_test.dart test/widgets/message/message_context_menu_overlay_test.dart` — 41 tests green (7 composer + 14 overlay files; 5 new).
- Tester agent mutation-proofed: reverting each of the 5 fixes fails exactly its one test, others stay green.
- `graphify update .` run (4501 nodes, 5691 edges).

## Notes for next session

- Branch `feat/emoji-reactions` at `ce0ee58`, pushed to origin. NOT merged to master — needs PR + on-device VM test before merge (per AGENTS.md branch workflow). Deploy goes live only after merge to master.
- Device QA checklist: field tap swaps panel→keyboard (no stacking), Android back closes panel first, send from panel keeps it open, mic dismisses panel, reaction sheet sits above open keyboard on iOS PWA.
- Known parity gap left intentionally: tapping the message list does NOT close the panel (Telegram closes it); wiring a chat-list tap handler was judged out of scope — flag if wanted.
- Suggested-reaction row kept in the composer picker (deviation from bare Telegram panel, but useful; remove via `showSuggestedRow: false` if the user objects).
