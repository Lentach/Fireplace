---
name: flutter-frontend-design
description: Build distinctive, production-grade Flutter UI (widgets, screens, apps) that avoids generic "AI slop". Use this skill WHENEVER building or restyling anything visual in a Flutter/Dart codebase — a widget, screen, dialog, list, animation, theme, or design system — even when the user just says "make this screen", "add a loading state", "polish this", or "make it look better" without naming design explicitly. Covers layout, theming/tokens, typography, motion (flutter_animate, animations, implicit animations, Hero), and the render→screenshot→critique loop. Prefer this over the generic web frontend-design skill anytime the target is Flutter, not HTML/CSS/React.
---

Build Flutter interfaces with real taste and working code. The goal is UI that looks intentionally designed — not the stock Material-defaults-on-white look that reads as AI filler. This skill is Flutter-native: it assumes Dart, widgets, `ThemeData`/`ThemeExtension`, and the Flutter render model, NOT CSS/DOM.

## The rule that matters most: render it and LOOK

Slop ships because the widget compiles and is never seen. Close this loop on every visual change before calling it done:

```
build → run (flutter run -d chrome, or a device) → screenshot → critique against the target → iterate
```

- Web (`flutter run -d chrome` / `flutter build web` served locally) is the fastest surface to render and screenshot. Actually look at the screenshot and judge it like a designer — spacing, hierarchy, contrast, alignment, rhythm. "It compiles" and "a widget test passes" are NOT visual verification.
- If the project has reference mockups/screenshots, compare against them. If it doesn't and the user has a target in mind (an app they like), ask for or generate a reference image and match it.
- Check **every theme** the app supports (light AND dark at minimum) and a couple of viewport widths. A color that works in one theme is often invisible in another; a layout that works at 400px breaks at 900px.

Flutter renders web to a canvas, so DOM-inspection tools see nothing useful — screenshots are the way to verify web visuals.

## Read the project's design system FIRST — never invent

Before writing colors/fonts/spacing, find and reuse what exists. Inventing values is the #1 slop source.

- Look for `ThemeData`, `ColorScheme`, custom `ThemeExtension`s, a `theme/` or `design/` dir, design tokens, and any `CLAUDE.md`/`STYLE.md`/design spec. Read them.
- Pull colors from `Theme.of(context).colorScheme` / the project's `ThemeExtension`, NEVER a hardcoded `Color(0xFF...)` in a screen or widget. If a needed color is missing, add it to the theme, not the widget.
- Match existing spacing/radius/elevation conventions and component patterns. A second convention living beside an existing one is a regression. Consistency is what reads as "designed."
- Respect any documented "this surface is intentionally X" decisions — don't restyle something the project deliberately kept plain.
- **Match dependency conventions.** Check `pubspec.yaml` before reaching for a package. Prefer Flutter's built-ins; add an animation/UI dependency only when it clearly earns its place AND the project accepts new deps (some repos are strict about this). Reusing what the project already has beats introducing a new library — never bias a UI toward effects just because some package exists.

If there is genuinely no system yet, establish a small one (a `ColorScheme` + a few `ThemeExtension` tokens + a type scale) and use it consistently rather than scattering literals.

## Aesthetics

Commit to a clear, intentional direction and execute it precisely — refined-minimal and bold-maximalist both work; timid middle-ground is what looks generic.

- **Typography:** use the project's existing font setup. When establishing type from scratch, pick a distinctive, readable pairing (a characterful display face + a clean body face) — `google_fonts` or bundled fonts both work. Avoid defaulting to the platform default everywhere. Build a real type scale (sizes, weights, line-height via `height`) rather than sprinkling ad-hoc `fontSize`s.
- **Color:** dominant colors with sharp accents beat evenly-distributed timid palettes. Drive everything through `ColorScheme`/tokens so light/dark and theming stay coherent. Meet WCAG contrast (≥4.5:1 for body text) — verify it, don't assume.
- **Layout & depth:** use whitespace deliberately; align to a grid; create depth with elevation, subtle shadows, layered surfaces, gradients, or texture instead of flat same-color-everywhere. `LayoutBuilder`/`MediaQuery` for responsive breakpoints. Avoid the default `Card` + `ListTile` + `ElevatedButton` stack with zero customization — that's the slop signature.
- **Detail:** consistent icon sizing/weight, considered empty states (not a bare `CircularProgressIndicator`), considered loading states (prefer skeletons over spinners where the project supports them), and pressed/hover/focus feedback.

## Motion

Motion makes UI feel alive — but uncapped, replayed, or unavoidable motion is a fancier slop. Reach for motion at high-impact moments (one orchestrated screen-in, a hero, a state transition), not scattered everywhere.

**Libraries & tools — built-ins first, dependencies only when they fit the project:**
- **Built-in implicit animations** (no dependency) cover most needs: `AnimatedContainer`, `AnimatedOpacity`, `AnimatedSwitcher`, `AnimatedAlign`, `TweenAnimationBuilder`, `Hero` (shared-element transitions), plus `PageRouteBuilder` for custom route transitions. Reach here first.
- If the project ALREADY uses a motion/UI package, use it. If not, adding one is a real cost — justify it and confirm the project accepts new deps first. Common, well-maintained options: `flutter_animate` (declarative entrances/micro-interactions, `widget.animate().fadeIn().slideY()`), `animations` (Flutter team; Material shared-axis / container-transform / fade-through), `skeletonizer` / `shimmer` (loading skeletons), `lottie` / `rive` (vector micro-animations).
- **`HapticFeedback.lightImpact()`** (built-in) for tactile confirmation on key actions (mobile).

**Motion spec (sensible defaults):**
- Entrances 150–300 ms; state changes 150–250 ms. Rarely exceed ~400 ms for UI chrome — long animations feel sluggish.
- Curves: `easeOut`/`easeOutCubic` for entrances, `easeInOut` for state changes. Avoid `linear` for UI.
- Subtle distance: slide offsets small (a handful of px, or `slideY` begin ≤ ~0.1), opacity 0→1. No fly-across-screen moves.
- **Stagger sparingly and capped.** Stagger only the initial visible batch (e.g. first ~6 items, ≤40 ms step); never `index * step` unbounded, or item 50 waits seconds.
- **Play entrances ONCE.** In reactive/rebuild-heavy trees (e.g. a list rebuilt by a state/store notify), guard entrances so they don't replay on every rebuild — track which elements already animated. Replaying the whole list on each state change is a classic slop tell.
- **Honor reduce-motion ALWAYS.** Check `MediaQuery.disableAnimationsOf(context)` (a.k.a. the OS "reduce motion" setting) and skip entrances / swap continuous shimmer for a static fill. Accessibility users must not be forced to watch motion.

**Where NOT to animate:** avoid entrance/size animations on keyboard-adjacent chrome (text composers, inputs that track the keyboard inset) — animating a large block through the keyboard show/hide window causes platform-specific flicker/jank on iOS/Android web. Prefer instant mount/unmount there. When in doubt, check the project's notes for documented "do not animate" zones.

## Platform notes

- Guard `dart:io`/`Platform` with `!kIsWeb`; use conditional imports for platform-specific code.
- iOS web keyboard insets are unreliable via `MediaQuery.viewInsets`; projects often have a dedicated helper — use it.
- Test the actual target platform. Web-canvas text rendering, iOS Safari, and Android differ; don't assume Chrome-desktop parity.

## Verify before yielding

- `flutter analyze` clean on touched files.
- Rendered and screenshotted across themes/viewports (the loop above).
- If the change is behavioral (loading gate, animation guard, responsive branch), add a focused widget test that defends it (e.g. reduce-motion swaps the effect; loading state shows only while actually loading).
- Match the project's existing conventions and lint rules; keep tests deterministic.

Remember: match implementation effort to the vision. Maximalist designs need elaborate code and orchestrated motion; minimalist designs need restraint and precise spacing/typography. Elegance is executing a clear intent well — not piling on effects.
