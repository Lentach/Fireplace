# Latest session summary

**Date:** 2026-05-15  
**Summary:** [2026-05-15-session-composer-mic-left-gesture-buffer.md](2026-05-15-session-composer-mic-left-gesture-buffer.md) — composer: **+14dp right padding** on compact layouts + **negative** `_kMicRestingOffsetX` (-6) to move mic/newline **left** away from edge gestures; tests **115** + graphify + CLAUDE.

**Previous:** [2026-05-15-session-composer-horizontal-safe-area.md](2026-05-15-session-composer-horizontal-safe-area.md) — composer: horizontal `SafeArea` only on message list; full-bleed input bar + `MediaQuery.padding` in `ChatInputBar`; tests **115** + graphify + CLAUDE.

**Previous:** [2026-05-15-session.md](2026-05-15-session.md) — **composer IME follow-up:** `onEditingComplete` prevents keyboard dismiss on Send; post-frame refocus; `ConstrainedBox` max height; newline `NoSplash` + `ExcludeFocus`; tests 115 + graphify + CLAUDE.

**Previous:** [2026-05-15-session-teal-stone-theme.md](2026-05-15-session-teal-stone-theme.md) — fourth theme **Teal + stone** (`themeDataTealStone`), settings eco icon + tooltips, `lightTheme` / bubble tick alignment; l10n + CLAUDE + graphify + tests.

**Previous:** [2026-05-15-session-light-sent-bubble.md](2026-05-15-session-light-sent-bubble.md) — light theme: sent bubble warm tint instead of solid orange; dark text + delivery tick colors + voice controls for contrast; CLAUDE + graphify + bubble tests.

**Previous:** [2026-05-15-session.md](2026-05-15-session.md) — chat composer newline: IME flicker fix (conditional `requestFocus` + `Focus` around trailing mic/newline), long-press layout glitch fix (replace Material `Tooltip` with `Semantics`); tests + graphify + `CLAUDE.md`.

**Previous:** [2026-05-15-session-mic-offset-tweak.md](2026-05-15-session-mic-offset-tweak.md) — tiny right shift for composer mic hit target to reduce edge-adjacent tap misses; behavior preserved; CLAUDE + graphify + lint checks.

**Previous:** [2026-05-15-session-voice-recording-followups.md](2026-05-15-session-voice-recording-followups.md) — voice recording bar l10n, abort in-flight start on long-press cancel, 500 ms min clip + recorder cleanup on early exit; analyze + tests + graphify.

**Previous:** [2026-05-15-session-voice-recording-gesture-fix.md](2026-05-15-session-voice-recording-gesture-fix.md) — voice hold-to-record: single `GestureDetector` + pending stop after async start; analyzer + graphify.

**Previous:** [2026-05-15-session-bottom-padding-tuning.md](2026-05-15-session-bottom-padding-tuning.md) — increased chat/nav bottom gesture-safe spacing after real-device tests.

**Previous:** [2026-05-11-session-android-desugar.md](2026-05-11-session-android-desugar.md) — Android: enable core library desugaring for `flutter_local_notifications` (`build.gradle.kts`); `assembleDebug` verified.

**Previous:** [2026-05-11-session-bottom-insets-fix.md](2026-05-11-session-bottom-insets-fix.md) — cross-device bottom inset fix for chat/action bars and bottom navigation, plus web viewport safe-area update.

**Earlier:** [2026-05-11-session-safe-area-audit.md](2026-05-11-session-safe-area-audit.md) — audit of bottom **SafeArea** / insets and identified hot spots.

**Earlier:** [2026-05-11-session.md](2026-05-11-session.md) — PWA badge dot + **`web-push-sw.js`** best-effort `setAppBadge` on push; iOS caveats in `CLAUDE.md`.

**Earlier:** [2026-05-10-push-client-state-fix.md](2026-05-10-push-client-state-fix.md) — push suppression fixes.
