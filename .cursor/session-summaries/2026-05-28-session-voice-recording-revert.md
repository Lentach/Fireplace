# Voice recording revert to 0.0.11 + CLAUDE.md cleanup

**Date:** 2026-05-28

## What was done
- Reverted `recording_controller.dart` to commit `1179892` (0.0.11) — removed all voice lock-up code (`_isLocked`, `_lockDragOffset`, `lockUpThresholdPx`, `_enterLockedMode`, lock-up UI, send/cancel locked buttons) that caused the UI to freeze when user slid mic up
- Deleted untracked tap-to-toggle rebuild stubs: `recording_config.dart`, `voice_recording_state.dart`
- Deleted `recording_controller_lock_test.dart` (tests for removed lock-up feature)
- Removed stale ARB keys from `app_en.arb` and `app_pl.arb`: `voiceRecordingSlideUpToLock`, `voiceRecordingLocked`, `voiceRecordingCancelLocked`, `voiceRecordingSendVoiceTooltip`, `voiceRecordingSendVoiceSemantics`, `voiceRecordingLockedSemantics`, `snackbarE2eAskSenderResend`
- Regenerated l10n
- Cleaned CLAUDE.md: removed stale voice lock-up documentation, updated recording regression test reference
- Added session workflow rules to CLAUDE.md (read LATEST at session start, write summary at task end, improved scope rule)

## Key files
- `frontend/lib/widgets/input/recording_controller.dart` — restored to 0.0.11
- `frontend/lib/widgets/input/recording_config.dart` — deleted
- `frontend/lib/widgets/input/voice_recording_state.dart` — deleted
- `frontend/test/widgets/input/recording_controller_lock_test.dart` — deleted
- `frontend/lib/l10n/app_en.arb` — 7 stale keys removed
- `frontend/lib/l10n/app_pl.arb` — 7 stale keys removed
- `CLAUDE.md` — voice lock-up docs removed, session workflow rules added

## Verification
- `flutter test test/widgets/input/recording_controller_test.dart test/widgets/input/chat_input_bar_disappearing_banner_test.dart` — ✅ 5/5 passed
- `flutter analyze` — ✅ 6 pre-existing warnings only, nothing related to our changes

## Notes for next session
- Voice recording is back to clean hold-to-record model (0.0.11): hold mic → slide left to cancel, release to send
- The tap-to-toggle rebuild spec exists in `.kiro/specs/voice-recording-rebuild/` but is deferred — start fresh when ready
- `chat_input_bar.dart` was already clean (zero diff from 0.0.11) — trailing send rollback from 0.0.15 was complete
- Current version is 0.0.15; next feature should bump to 0.0.16

## Additional: analyzer warnings fixed (same session)
- Removed dead field `_pendingHistoryDecryptAfterE2EReady` from `messaging_provider.dart` (written-only, never read — no behavioral change)
- Added `// ignore: use_build_context_synchronously` on GlobalKey context in `chat_detail_screen.dart`
- Removed redundant `!` from `chat_detail_pinned_banner_test.dart` (AppLocalizations.of() is non-nullable)
- Fixed `(_, __) {}` → `(_, _) {}` in `message_context_menu_overlay_test.dart`
- Removed unused `scalePad` variable in `message_context_menu_overlay_test.dart`
- Result: `flutter analyze` → No issues found, 246/246 tests pass

## E2E note for next session
- User reports [Decryption failed] placeholders visible to users — pre-existing bug, NOT caused by today's changes
- `_pendingHistoryDecryptAfterE2EReady` was written but never read — the retry it was supposed to trigger was never wired up
- Investigate: where should that field have been checked? Likely in `onE2EReady` or `_onSocketReady` callback
