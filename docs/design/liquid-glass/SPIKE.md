# Liquid Glass — package eval + performance spike (2026-07-10)

Throwaway harness: `.spike/spike_glass` (not shipped). Self-driving scene: 120-row chat list, every 3rd row a 320×220 noise bitmap ("media-heavy"), 3 down/up sweeps of 1s each per mode, `SchedulerBinding.addTimingsCallback` FrameTiming capture, results published to `document.title` (web) / stdout (Android). Jank threshold: total frame span > 16.7 ms.

## Modes

- `baseline` — no chrome.
- `hand` — one 66px nav pill: `ClipRRect` → `BackdropFilter(ImageFilter.compose(blur σ22, ColorFilter.matrix saturate 1.7))` + tint/border, `RepaintBoundary`-isolated.
- `hand5` — representative full chat chrome: 3 top capsules + composer pill + nav pill (5 independent BackdropFilters).
- `pkg` — `liquid_glass_widgets 0.21.3` `GlassContainer`, package-correct composition (`LiquidGlassWidgets.initialize()` + `wrap()`, grouped mode).
- `fake` — opaque-ish tint (α0.85) + border + shadow, no filter (the NO-GO fallback).

## Flutter web, RELEASE, CanvasKit — the shipping renderer (headless Chromium 141, desktop RTX-class GPU, Win11)

| mode | frames | build avg/p90/p99 ms | raster avg/p90/p99 ms | frames >16.7ms |
|---|---|---|---|---|
| baseline | 1435 | 1.21 / 1.9 / 2.5 | 0.45 / 0.6 / 0.8 | 0 |
| hand | 1438 | 1.16 / 1.7 / 2.2 | 0.78 / 1.0 / 1.2 | 1 (0.1%) |
| **hand5** | 1429 | 1.25 / 1.8 / 2.3 | **1.52 / 2.0 / 2.7** | 1 (0.1%) |
| pkg | 1431 | 1.31 / 1.9 / 2.5 | 0.94 / 1.2 / 1.6 | 1 (0.1%) |
| fake | 1428 | 1.04 / 1.6 / 2.0 | 0.50 / 0.7 / 0.8 | 0 |

The full 5-surface chat chrome costs ~1.1 ms raster over baseline on this GPU — comfortably inside budget, zero sustained jank. Numbers are desktop-GPU; NOT phone-representative. Mobile performance remains an open gate until measured on a physical phone browser (see Verdict).

## Android emulator (Pixel_7 AVD, x86_64, host-GPU translation) — FUNCTIONAL SMOKE ONLY

All modes render correctly, no crashes. Timings are NOT device-representative (the emulator can't even hold baseline: 11.3 ms raster avg / 70% frames over budget before any glass). Deltas for the record: hand +4.0, hand5 +5.0, pkg +3.6 ms raster avg over baseline. Real-device perf = owner device QA on the deployed branch. Note: production mobile is the PWA (web renderer), not a native Android build — the web column above is the shipping path.

## Package eval — `liquid_glass_widgets 0.21.3`

Health: MIT, 345★/45 forks, active (pushed 3 days before eval), single maintainer, pre-1.0 (0.21.x), requires Flutter ≥3.41 (we ship 3.44.6 — OK). Deps: equatable, flutter_shaders, logging.

Verified by running on web release:
- **Correct composition renders correctly** (`initialize()` + `wrap()`, grouped `GlassContainer`): blur bounded to the pill, content sharp. Minimal repro: `.spike/spike_glass/lib/repro.dart`.
- **Harness observation (not reduced to a minimal repro):** `useOwnLayer: true` + per-widget `settings` without the `initialize()`/`wrap()` scaffolding blurred the ENTIRE scene on web — silent misrender. The minimal CORRECT composition does not exhibit it; treat as an integration hazard of the API's mode matrix rather than a confirmed package bug.
- **API-shape conflict:** per-widget `settings` (tint/blur per surface) are IGNORED in grouped mode and only honored via `useOwnLayer: true` — the mode that misrendered. Our spec needs per-surface, per-theme tints; the package's premium features (refraction, jelly physics) are Impeller-only, i.e. dead weight on our shipping web renderer.
- Timing: slightly slower than plain BackdropFilter (0.94 vs 0.78 ms raster avg, 1-pill scene).

## VERDICT

- **Performance: web-desktop GO** for the hand-rolled recipe. **Mobile-device: UNRESOLVED** — emulator is functional-only; the remaining gate is a real mobile-browser measurement (this harness served over LAN to a physical phone, results shown on-screen) BEFORE the redesign ships. Fake-glass fallback (§7 of SPEC.md) stays wired as the escape hatch.
- **Dependency: DO NOT ADOPT `liquid_glass_widgets`.** Hand-rolled `GlassSurface` wins on: exact spec control (σ22 + saturate 1.7 + per-theme tint/border/highlight ≈ 40 lines), cheaper raster, zero dependency/API-churn risk (pre-1.0, single maintainer), no silent-misrender foot-gun, no unused Impeller-only feature weight.
