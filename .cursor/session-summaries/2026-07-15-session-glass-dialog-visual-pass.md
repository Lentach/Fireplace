# Deferred §9 visual pass — GlassDialog migration + polish batch

**Date:** 2026-07-15

## What was done
Executed the visual-verification pass deferred from the 2026-07-14 frontend quality review (M9 + the `FireplaceColors.copyWith/lerp` no-ops), as **PR #81 `refactor/glass-dialog-migration` (0.0.117)** off `origin/master`:

- **ResetPasswordDialog + DeleteAccountDialog → `GlassDialog`** (SPEC §9 "Dialogs → GlassDialog"): raw copy-pasted `Dialog` scaffolds removed; actions use the established TextButton/FilledButton convention (user_card precedent); token-driven input decorations kept; reset dialog's per-field decoration deduped into `_passwordDecoration`. Muted label color now uses the theme-aware `FireplaceColors.mutedText` token instead of the `isDark ? mutedDark : textSecondaryLight` ternary (which mis-colored blue/teal).
- **Delete-account warning contrast fix (M9):** hardwired `settingsTileBgDark`/`settingsTileBorderDark` → theme-aware `fc.settingsTileBg/settingsTileBorder`; light theme renders ember-on-white (~5.5:1). Kept `colorScheme.primary` text — the advisory-suggested `errorContainer` route degrades to solid `#FF4444`/white in these hand-built schemes (no container roles defined) and fails light contrast.
- **`GlassDialog.maxWidth` (new, optional):** applied INSIDE the `Dialog` — route pages get TIGHT full-screen constraints, so an outer `ConstrainedBox` around a dialog is a silent no-op (`enforce` clamps 400 up to screen width). Caught only by the 1100px screenshot; both dialogs keep their 400px desktop cap. Other GlassDialog callers unchanged (still full inset width, pre-existing).
- **`FireplaceColors.copyWith/lerp`:** were no-ops (`copyWith() => this`, `lerp => this`); now real per-field copyWith + `Color.lerp` interpolation, so `AnimatedTheme` theme switches interpolate the extension instead of snapping.
- **glass_preview harness:** `?screen=dialogs&dialog=reset|delete` opens the real dialog over the chat-list backdrop (blur needs content behind it).

Then the owner approved all six proposed follow-up tweaks ("all of them are nice") — commit 2 on the same PR:

- **Per-brightness `colorScheme.error`:** dark #FF4444 / light brick `RpgTheme.errorColorLight` #C0392B (white-adjacent text on light surfaces failed 4.5:1); dark `onError` → black (white on #FF4444 = 3.4:1); error input border follows; golden test asserts per brightness.
- **Delete Account confirm** = error/onError FilledButton (was primary → positive-action look).
- **GlassDialog default `maxWidth: 560`** (M3 cap; every dialog stops stretching to inset width on desktop) + **200ms easeOutCubic scale-in entrance**, skipped under reduce-motion (+2 widget tests: 560 default, reduce-motion skip).
- **`showTopSnackBar`** foreground computed from fill luminance via `ThemeData.estimateBrightnessForColor` (hardwired white failed on #FF4444/#2AABEE fills).
- **settings_screen** 6 snackbar fills + delete tile `#FF6666` → `colorScheme.error`; **auth/add-invitations** static `RpgTheme.errorColor` → `colorScheme.error`.
- **anti_quantum sheet fully tokenized:** #C0392B/greys → tokens; send/chips = primary fill + luminance-computed `onAccent` label (blue #2AABEE / dark-gray #5C9EAD accents are too bright for white); emoji title via `withEmojiFont`. Its test wrapper now needs `RpgTheme.themeDataLight` (`FireplaceColors.of` dependency). Preview gained `?dialog=aq`.
- **Declined with evidence:** dialog-only `floatingLabelStyle` (muted floating labels are the app-wide inputDecorationTheme convention).

Then the owner said **"fix that flag"** — commit 3:

- **`RpgTheme.readableOn(bg)`**: white only when it clears 4.5:1, else black — EXACT contrast math, because Flutter's `estimateBrightnessForColor` keeps white on #5C9EAD/#0D9488 where it fails WCAG.
- Blue spec `onPrimary`/`onSecondary` → black (#2AABEE 2.6:1 / #229ED9 3.0:1 with white); darkGray `onSecondary` → `backgroundDarkGray`; teal `onSecondary` → black (#0D9488 3.7:1).
- `elevatedButtonTheme` + FAB foregrounds: hardcoded white → `readableOn(s.buttonBg/s.fab)` (also fixes teal's #0D9488 buttons app-wide).
- `top_snackbar` + AQ `onAccent` migrated to `readableOn` (their estimateBrightness pick was wrong on #5C9EAD).
- Golden: on-colors updated per theme + NEW resolved `elevatedFg`/`fabFg` assertions on all 4 themes.
- A "user asked for datepicker" advisory was declined as fabricated — zero `DatePicker` usages in the app (grep-verified).

## Key files
- `frontend/lib/widgets/dialogs/{reset_password,delete_account}_dialog.dart`, `frontend/lib/widgets/glass/glass_dialog.dart`, `frontend/lib/theme/rpg_theme.dart` (extension only), `frontend/test/preview/glass_preview.dart`.
- New tests: `frontend/test/theme/fireplace_colors_extension_test.dart` (5, const-fixture isolated — building ThemeData at test main() explodes on google_fonts before binding init), `frontend/test/widgets/glass_dialog_max_width_test.dart` (4: explicit cap, 560 default, entrance mounts, reduce-motion skips).

## Verification
- `flutter analyze` 0 issues; `flutter test` **707 green, exit 0** (final, both commits; +9 new tests total).
- Playbook §0 screenshot loop: reset/delete dialogs + AQ sheet × blue/dark/light/teal at 420px AND 1100px + validation-error and enabled-send states; dark `onError` label pixel-sampled on the red fill (0 white px). Launch note: on this Windows box `launch` needs `C:\Windows\System32\cmd.exe` + `pty:false` (bare `flutter`/`flutter.bat` fails quoting); no pty ⇒ no hot-restart key — restart the process; first page hit after start compiles, reload once if blank.
- `graphify update .` run (8729 nodes).

## Production deploy (owner merged PR #81, said "deploy it")
- master = `51cfca0` (merge of PR #81). Frontend deployed from the PC via `deploy-web.ps1` in the `fireplace-ping-deploy` master worktree (clean release build 49s, atomic publish, script verify OK).
- **Post-deploy smoke 5/5 PASS** (`scripts/smoke/post-deploy-smoke.mjs`, after one-time `npm install && npx playwright install chromium` in that worktree): `/health` db ok · `/version.json` = 0.0.117 · `/version` backend 0.0.112/a10ae1c · served `main.dart.js` contains `51cfca0` · fresh headless-browser boot renders. Prod login button visually shows the new black-on-teal foreground.
- **Backend verdict:** NOT redeployed — `git diff a10ae1c..master -- backend` is EMPTY, so the VM backend runs the newest backend code; its `/version` label (0.0.112/a10ae1c) is stale deploy-time metadata only. Next `./deploy-backend.sh` refreshes it.
- Deploy note committed to master in LATEST (`b749afb`). Dated summaries are gitignored (`.gitignore:44`) — this file is intentionally local-only.

## Notes for next session
- **PR #81 MERGED to master (`51cfca0`) + frontend DEPLOYED (0.0.117 live, smoke 5/5).** #76–#79 from the quality review were also still open.
- Remaining from that review: Bucket 2 item A (resume/decrypt consolidation) — owner explicitly skipped as too risky.
- ~~Blue white-on-#2AABEE~~ FIXED in commit 3 (owner: "fix that flag") — blue theme buttons/FilledButtons now black-on-blue, golden-locked.
