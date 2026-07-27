# Long-message "Read more" collapse + toast back-arrow reposition

**Date:** 2026-07-15 (Two follow-up fixes the previous chat-minor-bugs batch failed to deliver. Branch `fix/msg-collapse-toast-position`, 0.0.119)

## Context — why the previous agent (0.0.118, PR #82 merged) failed these two
1. **Notification covers back arrow.** Previous fix wrapped `showTopSnackBar` in `IgnorePointer` — that only makes taps pass THROUGH the toast; the opaque fill still sat at `top:0`, visually covering the app-bar back arrow for the whole 2.5s. Wrong sub-problem (tap interception vs. visual overlap).
2. **Long messages don't "wrap up".** The 0.0.118 commit (`947088d`) touched **zero** log/text renderers — the item was silently dropped from the batch. Literal line-wrapping already works (verified: chat `RichText` + diag `SelectableText` both wrap at bounded width). The user's actual ask (confirmed via image1 = Telegram "Read more" collapse): **long normal chat messages must collapse behind a Read-more toggle so one message can't fill the screen.** Never implemented.

## What was done
- **Toast position** (`widgets/top_snackbar.dart`): moved the overlay from `top:0` to `topInset + GlassTopBar.capsuleHeight + 16 + 8` (below the app-bar band). `topInset` is snapshotted from the **caller** context (not the root OverlayEntry ctx) so it matches the triggering screen's inset. Kept `IgnorePointer` (informational overlay never intercepts taps).
- **Long-message collapse** (`widgets/message/text_message_content.dart`): `StatelessWidget → StatefulWidget`. Body spans built once, reused for both a `TextPainter` measurement (`maxLines = AppConstants.maxCollapsedMessageLines = 12`, same `textDirection`/`textWidthBasis`, unscaled — matches the RichText) and the displayed `RichText`. When `didExceedMaxLines`: collapsed view clips to 12 lines + ellipsis with a **Read more** toggle; expanded shows full text + **Show less**. `didUpdateWidget` resets `_expanded` on `message.id` change (list-recycling safety). Jumbo emoji + Anti-Quantum-Note paths untouched (never collapse). Toggle color mirrors the file's link convention (mine → textColor, received → colorScheme.primary).
- l10n `messageReadMore`/`messageShowLess` (en: "Read more"/"Show less"; pl: "Czytaj więcej"/"Zwiń") + regen.
- `AppConstants.maxCollapsedMessageLines = 12`.
- Toggle color = `colorScheme.primary` (accent) on **both** sides — the white body text on sent bubbles made a same-color toggle unreadable (owner-reported); accent matches the app's link/tab treatment.

## Key files
- `frontend/lib/widgets/top_snackbar.dart`, `frontend/lib/widgets/message/text_message_content.dart`
- `frontend/lib/constants/app_constants.dart`; l10n en/pl arb + generated
- new tests: `test/widgets/top_snackbar_position_test.dart`, `test/widgets/text_message_collapse_test.dart`
- `frontend/pubspec.yaml` 0.0.118 → 0.0.119

## Verification
- Both fixes **visually verified** via throwaway `tool/*_preview.dart` harnesses rendered in Chrome at 390×844 (deleted after): toast sits clearly below the back arrow/title; long log collapses to 12 lines + "Read more", tap expands to full + "Show less".
- `flutter analyze --no-fatal-infos`: **No issues**. `flutter test`: **718 passed** (714 prior + toast-position + 2 collapse cases).
- **DO NOT run `dart format`** on the tree (Dart 3 tall style reflows the repo; CI doesn't enforce). Hand-formatted.

## Notes for next session
- **PR #83 MERGED to master + frontend DEPLOYED** (`git push 25027e1`, `deploy-web` bundle published via manual scp+swap; `/version.json` = 0.0.119, `main.dart.js` carries `25027e1`, `/health` ok). Backend unchanged → `/version` still 0.0.118 (frontend-only PR; runbook permits). Docs follow-up `3a671bd`.
- NOTE: `deploy-web.ps1` in the `fireplace-ping-deploy` worktree kept showing as deleted (` D`) after each script run — restored via `git checkout`; publish was done manually (ssh/scp + atomic swap) since the PowerShell script stalled silently at the ssh step in this shell. SSH key auth to `ubuntu@51.68.138.13` works fine.
- Collapse threshold is 12 wrapped lines (`AppConstants.maxCollapsedMessageLines`); tune if the fold feels too tall/short on device.
- The diagnostic hacker-mode panel was code-inspected as bounded/wrapping (not separately render-tested) — user explicitly scoped the ask to normal chat messages, not the diag window.

## Previous
- 2026-07-14: Chat minor-bugs batch (8 fixes) — `fix/chat-minor-bugs` 0.0.118, **PR #82 MERGED**. Two items failed (this session fixes them). Full: `2026-07-14-session-chat-minor-bugs.md`.
- 2026-07-15: Deferred §9 visual pass + polish + bright-accent contrast fix; **PR #81 MERGED + DEPLOYED, 0.0.117 live**. Full: `2026-07-15-session-glass-dialog-visual-pass.md`.
- 2026-07-14: Frontend quality review — audit + Buckets 1/2; #71–#75 MERGED, #76–#79 open. Full: `2026-07-14-session-frontend-quality-review.md`.
- 2026-07-14: Emote button removal + red-heart FONT root-cause (`withEmojiFont`); `fix/emote-button-and-red-heart` 0.0.115. Full: `2026-07-14-session-emote-button-red-heart.md`.
