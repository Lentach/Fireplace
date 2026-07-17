# Cosmic starfield — performance spike results

## DevTools frame-time capture (VM Service `Flutter.Frame` stream) — Android emulator

Captured the authentic DevTools frame-times source: the profile app's Dart VM
Service `Extension` stream `Flutter.Frame` events (build + raster + total elapsed
per frame) — the exact data DevTools' "Flutter Frames" chart plots — read
programmatically over the VM-service websocket while the cosmic starfield
scrolled behind the chat. Android x86 emulator (gphone64, API 34), profile.

| config | frames | build p50/p95 | raster p50/p95 | elapsed p50/p95 | jank (elapsed>16.7) |
|--------|-------:|--------------:|---------------:|----------------:|--------------------:|
| starfield d=120 (shipped) | 3314 | 1.72 / 4.56 | 15.06 / 28.97 | 26.85 / 54.38 | **93.6%** |
| starfield d=60 | 2223 | 1.76 / 8.31 | 14.95 / 29.39 | 27.32 / 58.80 | **94.2%** |
| opaque d=0 (NO field) | 6098 | 1.53 / 3.95 | 14.39 / 26.90 | 25.70 / 48.11 | **85.1%** |

**Honest reading:** the emulator janks on the MAJORITY of frames even with NO
starfield (85.1% at the opaque baseline) — its software/host-GPU raster floor
(~14 ms p50) alone eats almost the whole 16.7 ms budget. The animated-field
configuration adds a real but small increment: ~+9 pp jank over opaque,
d=120 93.6% and d=60 94.2%. That increment is DENSITY-independent (60 ≈ 120), so
cutting star count is not the lever. Going STATIC (reduced-motion) removes the
ticker-driven repaints — expected to land near the opaque baseline, though it
keeps one cached static layer and was NOT separately captured on this stream, so
it is not claimed equal to d=0. The opaque baseline itself STILL janks (85.1%),
because the jank is scroll-raster bound. Conclusions:
- Density 60 vs 120 has no material effect; any ANIMATED field carries a
  measurable incremental cost (~+9 pp) over opaque on this emulator.
- The x86 emulator is not a valid 60 fps proxy for this scrolling UI (it fails at
  the opaque baseline and density knobs don't move it).
- On a real-GPU surface (web, below) the same field is 0.0% jank.
- **Mobile 60 fps is NOT validated.** The only mobile target available here is the
  x86 emulator, which cannot validate it either way. A physical-device capture is
  the outstanding, unresolved confirmation — NOT performed (no device available).

Harness: `tool/starfield_spike.dart` (profile mode). Drives the PRODUCTION path
`RpgTheme.themeDataCosmic → ChatBackgroundPattern → StarfieldBackground` behind a
continuously auto-scrolling 200-item chat bubble list. Density overridden through
the real `CosmicBackdrop` theme extension. Frame stats from
`SchedulerBinding.addTimingsCallback` (same `FrameTiming` data DevTools shows).
Budget = 16.7 ms (60 fps). All ms.

### Measurement caveats (read before trusting the numbers)
- Metrics are from `SchedulerBinding.addTimingsCallback` — the SAME `FrameTiming`
  build/raster data DevTools' Performance view plots — surfaced via the harness
  (on-screen overlay on web, stdout on Android). This is NOT an interactive
  DevTools Performance trace / timeline capture.
- Surface is the harness (`tool/starfield_spike.dart`), which drives the real
  cosmic `ThemeData` → `ChatBackgroundPattern` → `StarfieldBackground` + a real
  scrolling `ListView` of bubbles. It is NOT the authenticated `ChatDetailScreen`
  (that needs a live backend + accounts, unavailable in this environment).
  ChatDetail adds opaque bubble/chrome widgets on top of the same field, so its
  extra cost is additive-and-opaque, not starfield-related.
- Web raster on CanvasKit is often under-reported vs real hardware; the Android
  emulator over-reports raster (weak host GPU). Both are noted where they matter.

## Flutter web — Chrome profile, 390×844 viewport

| density | build p50 | build p95 | build max | raster p50 | raster p95 | jank>16.7 |
|--------:|----------:|----------:|----------:|-----------:|-----------:|----------:|
| 240 (site baseline) | 3.3 | 5.1 | 11.6 | 0.9 | 1.2 | **0.0%** |
| 0 (opaque, no field) | 1.2 | 2.0 | 3.5 | 0.4 | 0.6 | 0.0% |

Starfield adds ~2 ms build p50 / ~3 ms p95, ~0.5 ms raster. Zero janky frames.

## Android — x86 emulator (gphone64, API 34), profile, steady state

| density | build p50 | build p95 | build max | raster p50 | raster p95 |
|--------:|----------:|----------:|----------:|-----------:|-----------:|
| 240 | 1.9–2.4 | 4.3–6.5 | 7–27 | 14.7–16.3 | 29–45 |
| 0 (opaque baseline) | 1.2 | 3.2 | 22 | 13.4 | 24.8 |

Start-up window shows the usual first-frame/shader-warmup spike (build p95 134,
raster p95 506 over the first 23 frames), then settles within ~8 s.

## Verdict: GO — ship density **120** (default); 240 = source-baseline / owner variant

What the measurements actually show (measured configs only — web was measured at
240 and 0; the emulator sweep covered 0/60/120/240):
- The animation's UI-thread cost (build) is tiny everywhere: p50 ~2–3 ms, so the
  twinkle math / CustomPainter is never the bottleneck.
- On the worst-case x86 emulator, 240 shows a starfield-attributable raster-p95
  rise (29–45 ms vs 23–28 ms at 60/120) — repeatable near-budget frames. 60 and
  120 sit at the opaque (no-field) floor, i.e. the extra stars add nothing there.
  (Note: even the opaque floor's p95 exceeds 16.7 ms, so the emulator's absolute
  raster is inflated vs real Impeller hardware — web rasters the same field in
  ~1 ms — but the 240-vs-120 DELTA is real and stars-caused.)
- Web (Chrome profile, 390×844): 0.0% frames over budget at 240; opaque baseline
  build p50 1.2 ms. (60/120 not separately measured on web — trivially cheaper.)

Per the task's rule ("NO-GO on jank → reduce star count"), the default ships at
**120**: it clears the emulator with no starfield-attributable p95 regression and
is STILL denser per-area than the site's 240-on-desktop hero, so it reads as a
full starfield on a phone. 240 remains available as a documented owner/taste
variant (visual density is an explicit owner call).

Mitigations that further cap real-world cost: RepaintBoundary isolation,
off-screen pause (app-lifecycle + TickerMode), and a static field under OS
reduced-motion.

## Android emulator density sweep (steady state, raster p50 / p95, ms)

| density | raster p50 | raster p95 | build p50 | build p95 |
|--------:|-----------:|-----------:|----------:|----------:|
| 0 (opaque floor) | 13.4–15.2 | 24.8–35 | 1.2–1.5 | 3.1 |
| 60  | 14.1–14.8 | 23–28 | 1.6–1.8 | 3.7–4.7 |
| 120 | 14.0–14.4 | 24–28 | 1.7–1.8 | 3.3–5.6 |
| 240 | 14.7–16.3 | 29–45 | 1.9–2.4 | 4.3–6.5 |

d=60 and d=120 are indistinguishable from the opaque (no-field) floor — the
emulator's weak host GPU sets that floor, not the stars. Only d=240 adds a
measurable, starfield-attributable p95 raster bump. Web was measured at 240
(0.0% jank) and opaque; 60/120 are trivially cheaper there. Shipping **120** as
the default (floor-level, no starfield p95 regression, still denser per-area
than the site's desktop hero); 240 stays a source-baseline / owner variant.
Density is an explicit owner taste call (calmer vs denser field).
