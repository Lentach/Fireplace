# Frontend quality review (full audit) + Bucket 1 safe fixes

**Date:** 2026-07-14 (senior quality audit of the entire Flutter frontend + 3 executed safe-fix PRs; branches UNMERGED)

## What was done
Full senior-grade quality review of the entire frontend (208 lib files, ~36.5k LOC) to judge real quality vs "AI band-aid debt", then executed the safe/high-value fixes (owner appetite: audit-first, then execute Bucket 1).

**Audit (100% coverage, verified):** 14 ordered chunks, leaf→crown. 10 read-only scouts opened every file in chunks A–K with file:line citations; the lead read the crown jewels directly (E2E encryption, message send/decrypt, composer/keyboard, socket/connection, chat_detail). Programmatically confirmed all 208 files map to a reviewed chunk (0 orphaned). Full audit artifacts are LOCAL-ONLY in `.planning/frontend-quality-review/` (gitignored — the repo is public; a weakness catalogue must not ship): `task_plan.md`, `progress.md`, `findings.md`, `QUALITY_REPORT.md`, `REFACTOR_PLAN.md`.

**Verdict:** NOT a band-aid stack. The crown subsystems (E2E `_sessionTails` serialization, `saveDecryptedContent`, pending-send lost-ack store, `_encryptAndSend` exactly-once latch, conditional-import shims, glass/theme token layer) are intentional scar-tissue with documented field-incident rationale and regression tests. Empty catches are ~90% disciplined dispose-guards. Debt lives in the outer UI layer: duplication, a few plain bugs, localization gaps, and defensive timer-accretion in the resume/decrypt path (4 overlapping triggers — works, but drift; flagged for owner-approved Bucket 2).

**Executed — Bucket 1, three PRs off `master` (`1904c85`), all UNMERGED:**
- **PR #71 `fix/frontend-correctness-bugs` (0.0.116):** (1) `ConversationModel.copyWith` couldn't clear-to-null → disappearing-timer OFF was ignored on the non-initiating peer (added `clearDisappearingTimer` flag + 2 regression tests); (2) recorder `stop()/dispose()` guarded so a throw can't wedge the recording bar; (3) `main.dart` native Firebase init no longer rethrows before `runApp` (was whole-app blank-screen crash); (4) `api_service` checks HTTP status before `jsonDecode` in 9 methods (non-JSON 502/timeout bodies were opaque `FormatException`).
- **PR #72 `fix/localize-auth-screen`:** auth_screen + auth_form hardcoded English → ARB keys (en+pl); `_handleSubmit` loading `finally`.
- **PR #73 `chore/frontend-cleanup`:** avatar per-mount cache-bust removed (URLs are unique-UUID per upload); deleted dead `app_config_web/io`; analyzer now 0 issues (jumbo `\p{}` false-positive ignore + `context.mounted`); shared `isIOSWebKit()`; accurate VAPID comment; removed dead `muted` param, dead dialog `_isLoading`, 5 unused RpgTheme statics + `themeData` alias.

## Key files
- Audit: `.planning/frontend-quality-review/*` (local-only).
- PR#71: `models/conversation_model.dart`, `providers/conversations_provider.dart`, `widgets/input/recording_controller.dart`, `main.dart`, `services/api_service.dart`, `pubspec.yaml` (0.0.116), + `test/models/conversation_model_test.dart`, `test/providers/conversations_provider_test.dart`.
- PR#72: `lib/l10n/app_{en,pl}.arb` (+ generated), `screens/auth_screen.dart`, `widgets/auth_form.dart`.
- PR#73: `widgets/avatar_circle.dart`, `utils/jumbo_emoji.dart`, `screens/privacy_safety_screen.dart`, `services/push_service.dart`, `services/web_push_bridge_web.dart`, `widgets/message/message_action_panel.dart`, `widgets/dialogs/{reset_password,delete_account}_dialog.dart`, `theme/rpg_theme.dart`, deleted `config/app_config_{web,io}.dart`.

## Verification
- PR#71: `flutter analyze --no-fatal-infos` = 2 pre-existing infos; `flutter test` = **681 passed** (679 + 2 new).
- PR#72: analyze = 2 pre-existing infos; test = **679 passed**.
- PR#73: analyze = **No issues found (0, down from 2)**; test = **679 passed**.
- `graphify update .` run (8675 nodes). All branches pushed; PRs #71/#72/#73 open against master.

## Notes for next session
- **3 Bucket-1 PRs UNMERGED** off `master` (`1904c85`, live prod line). Only PR#71 bumps version (0.0.116); #72/#73 don't touch pubspec (no collision). Merge order arbitrary; whichever merges after #71 carries 0.0.116.
- **Bucket 2 (owner-approve, NOT executed)** in `REFACTOR_PLAN.md`: resume/decrypt 4-trigger consolidation (HIGH risk, crown path, needs `test_e2e` harness); shared encrypted-media loader (image/gif/file triplication); rpg_theme 4×-ThemeData→factory; add_or_invitations logic-out-of-build; bubble twin-branch dedup; auth boot-pyramid flatten.
- **Deferred to a visual-verification pass (§9 screenshot loop):** GlassDialog migration + delete-dialog light-theme contrast fix + `FireplaceColors.copyWith/lerp` no-ops.
- Owner Q's still open: Q4 (which Bucket-2 items to plan into PRs). Q1/Q2/Q3/Q5 answered (green-lit Bucket 1 / 0.0.116 / avatar unique-UUID so no backend change / branch off master).

## Addendum — Bucket 2 recommended refactors executed (PRs #75, #76)
Owner said "do recommended" (the two best value/risk items). Both executed as separate PRs off `master`, UNMERGED:
- **PR #75 `refactor/encrypted-media-loader`** (M7): image/gif/file shared an identical fetch→size-guard→optional-AES-GCM-decrypt pipeline. Extracted to `utils/encrypted_media_loader.dart` (`loadDecryptedMediaBytes`, throws on failure, injectable api/crypto). Each call site keeps its exact failure UI. +3 unit tests. Behavior-preserving (widget build/layout untouched → no visual delta; screenshot step honestly dropped: pure plumbing, real media needs a backend). analyze 2 pre-existing infos; test **682**.
- **PR #76 `refactor/theme-factory`** (M6): 4 near-identical ThemeData builders → `RpgTheme._buildTheme(_ThemeSpec)` + 4 const specs; rpg_theme.dart 844→600. Gated by a NEW field-by-field golden test locking all 4 themes vs the source-of-truth constants — green BEFORE and AFTER (proves the factory reproduces each theme incl. the ~6 per-theme quirks). Field-level golden replaces fragile screenshots for a behavior-preserving refactor + is the theme layer's first drift guard. analyze 2 pre-existing infos; test **683**.
- Remaining Bucket 2 (resume/decrypt consolidation, add_or_invitations, bubble dedup, auth boot-pyramid) still owner-approval.
