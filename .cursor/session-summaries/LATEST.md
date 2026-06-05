# Latest session summary

**Date:** 2026-06-02

**Topic:** Resumed the tap-to-toggle voice-message work interrupted by an unrelated PC crash. All 8 implementation tasks were already committed (`24fb05a`..`6bd14a1`); ran the never-executed **Task 8 verification** — `flutter analyze` clean, targeted voice tests +12, full suite +266, all green, no regressions. Finished the one Task 7 loose end (§7 `ChatInputBar` trailing-slot bullet in CLAUDE.md). v0.0.30. **Manual device QA (spec §6.4) still pending.**

→ [2026-06-02-session-voice-tap-to-toggle-verification.md](./2026-06-02-session-voice-tap-to-toggle-verification.md)

**Previous:** 2026-06-01 — Reduced `CLAUDE.md` 440→284 lines (−35%) at moderate level — collapsed the §2 flowchart, §3 file map, and §4 DB erDiagram (all derivable from code) and tightened the iOS keyboard-inset bullet; every non-obvious gotcha preserved. → [2026-06-01-session-claudemd-reduction.md](./2026-06-01-session-claudemd-reduction.md)

**Earlier:** 2026-06-01 — iOS composer floats — root-caused (Flutter viewInsets=0 while keyboard up), fixed via visualViewport-derived keyboard inset. **CONFIRMED fixed on iPhone.** Overlay kept as a toggle-gated dev tool (long-press chat title). v0.0.29 (commit da48c74). → [2026-06-01-session-ios-visualviewport-keyboard-inset.md](./2026-06-01-session-ios-visualviewport-keyboard-inset.md)
