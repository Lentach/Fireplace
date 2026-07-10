# Fireplace — Liquid Glass Design Spec (ACCEPTED 2026-07-10)

Owner-accepted from round-1 mockups (`docs/design/liquid-glass/round1/index.html`), applied to **all 4 existing themes** (`blue`, `dark`, `light`, `teal`). Direction mapping: blue→Nightfall-dark, dark→TealSmoke-dark, light→Hearthglow-light, teal→TealSmoke-light. Default wallpaper: **flame/sparks** everywhere (owner pick). User-selectable wallpaper and new themes are OUT OF SCOPE.

## 1. Grammar (locked)

- Glass lives ONLY on floating chrome: top-bar capsules, floating pill bottom-nav (glass-capsule highlight on active tab), composer pill, action-panel pill, sheets/menus/dialog surfaces.
- Content stays OPAQUE: conversation rows and message bubbles are solid; rows sit directly on the scaffold (no glass, no translucency below 1.0 on text surfaces).
- Chrome FLOATS: inset rounded pills; content scrolls behind and blurs through.
- Chat screen gets a tiled flame-doodle wallpaper at whisper contrast over the base color.
- Every glass surface has an opaque fallback (reduced-transparency / low-end / renderer NO-GO).
- Glass is paint, not layout: identical geometry contract as today’s solid bars (composer/keyboard/viewport contract in frontend/CLAUDE.md untouched).

## 2. Glass recipe (all themes)

- Backdrop filter: **Gaussian blur σ = 22 logical px** + **saturation ×1.7**.
  - Flutter: `BackdropFilter(filter: ImageFilter.compose(outer: ImageFilter.blur(22, 22), inner: ColorFilter.matrix(saturation 1.7)))`, ALWAYS inside a `ClipRRect` bounding the pill.
  - Static glass surfaces isolated with `RepaintBoundary`; blur radius NEVER animated.
- Fill, border, top inner highlight (inset 0 1 0), and drop shadow are per-theme (§3).
- Shadows: dark themes `0 8 28 rgba(0,0,0,0.45)`; light `0 8 24` of a warm/cool tinted 14–16% black (exact per-theme values in mock CSS).

## 3. Per-theme glass values

| theme | glass fill | border | inner highlight | active capsule | onGlassMuted | onGlassAccent | wallpaper tint | date pill bg/text |
|---|---|---|---|---|---|---|---|---|
| `blue` | rgba(26,38,50,0.52) | rgba(170,215,255,0.14) | rgba(255,255,255,0.07) | rgba(42,171,238,0.24) | #B9C6CF | #8FD0FF | #7FB8E8 @ 0.05 | rgba(12,20,28,0.72) / #9FB4C4 |
| `dark` | rgba(32,36,40,0.52) | rgba(190,225,235,0.13) | rgba(255,255,255,0.06) | rgba(111,180,196,0.24) | #B9C6CF | #6FB4C4 | #8FC4D0 @ 0.05 | rgba(12,13,15,0.72) / #A3ACB0 |
| `light` | rgba(255,250,246,0.55) | rgba(255,255,255,0.75) | rgba(255,255,255,0.9) | rgba(194,65,12,0.16) | #5E5852 | #C2410C | #B0563A @ 0.075 | rgba(255,252,249,0.8) / #8A6A58 |
| `teal` | rgba(252,253,252,0.55) | rgba(255,255,255,0.75) | rgba(255,255,255,0.9) | rgba(15,118,110,0.14) | #484440 | #0A4F4A | #3E7A74 @ 0.07 | rgba(253,254,253,0.8) / #5C6B66 |

`onGlassMuted` replaces the theme muted color for ALL text/icons sitting on glass (nav labels, composer hint, inactive icons). `onGlassAccent` replaces the accent on glass where the accent is mid-luminance (blue status line, teal active label). Off-glass content keeps existing theme colors.

## 4. Content surfaces (opaque)

| theme | scaffold bg | sent bubble / text | received bubble / text | body text / muted |
|---|---|---|---|---|
| `blue` | #141E28 | #1F74BB / #FFFFFF | #222E38 / #E7EDF2 | #E7EDF2 / #8A9BA8 |
| `dark` | #16171A | #2A4A5A / #EAF4F7 | #24262B / #F0F2F3 | #F0F2F3 / #93999C |
| `light` | #F7F1EA | #FFDCC7 / #3B2317 | #FFFFFF / #241C17 | #241C17 / #8A7A70 |
| `teal` | #FAFAF8 | #0F766E / #FFFFFF | #FFFFFF / #1C1917 | #1C1917 / #78716C |

Accepted content deltas vs current app (contrast gate, disclosed at acceptance):
- `blue` sent bubble `#2481CC` → **#1F74BB**, text pure white (was 3.89:1 → 4.91:1).
- `teal` sent bubble `#0D9488` → **#0F766E**, text pure white (was 3.59:1 → 5.47:1).
- Base scaffold/messages-area tones shift slightly to the mock values in §4 (blue `#17212B`→`#141E28`, dark `#17181A`→`#16171A`, light `#F7F4F0`→`#F7F1EA`, teal `#FAFAF9`→`#FAFAF8`) plus matched bubble/text tones — accepted as part of the mock palettes.
- Scaffold/base tones per theme get the mock’s radial top glow (`bgGrad` in mock CSS) — subtle depth, optional if it fights existing scaffold code.

## 5. Capsule metrics

- Top chrome: floating row inset **14px sides, 8px below status bar**; circles/pills **52px tall**, radius 26. Chat list: avatar-circle (44px avatar inside 52 glass circle), flex title pill (centered title 17/650; status line 11.5 italic accent), add-circle with red badge. Chat screen: back-circle, title pill (name + typing/recording status), one trailing pill holding ⋮ + 40px avatar.
- Bottom nav: floating pill **66px tall**, radius 26, inset **34px sides, 22px bottom**; 3 items; active item = capsule (radius 20, padding 7×18) in `activeCapsule` + accent icon/label; inactive = onGlassMuted. Active Chat icon keeps the custom filled-bubble-with-lines glyph.
- Composer: floating pill **56px tall**, radius 28, inset **12px sides, 20px bottom** (+ keyboard inset per existing contract). Order unchanged: chevron toggle, emoji toggle, transparent text field (hint = onGlassMuted), 48×48 trailing mic/send stack (accent). Action panel when open = second floating glass pill below/above per existing stacking.
- Date separators (chat): replace divider+label with a centered solid mini-pill (radius 12, padding 5×12) using per-theme date-pill values — solid, NOT glass (content layer).
- Bubbles: radius 16 (tail corner 6 in mock — optional, current app uses uniform 16; keep uniform 16 if geometry tests object), max width 85%, existing paddings.

## 6. Wallpaper

- Tile: 240×240 logical px flame-doodle set (flames, 4-point sparks, crossed logs, ember dots, smoke curls, marshmallow stick), stroke 2.2, round caps/joins — SVG master in `docs/design/liquid-glass/round1/` generator; ship as a `CustomPainter` or pre-rasterized cached tile (`ImageRepeat.repeat`), NEVER a runtime SVG dependency.
- Per-theme stroke color/opacity in §3 (`wallpaper tint`). Painted over base color + optional radial top glow. Replaces the current 18px dot pattern in `ChatBackgroundPattern` (chat screen only).
- One default wallpaper per theme; user selection = future feature, out of scope.

## 7. Opaque fallback (accessibility / low-end / NO-GO)

Every glass surface swaps to: solid fill = theme `colorScheme.surface` (existing values), same border color at alpha 1.0 equivalent (`convItemBorder`/`tabBorder`), same radii/metrics/shadow, no blur, no saturation. Trigger: (a) explicit user setting if added later, (b) `MediaQuery.highContrast` (reactive), (c) compile-time kill-switch `flutter build web --dart-define=REDUCE_TRANSPARENCY=true` (the NO-GO ship mode) — fake-glass then means: same fills as §3 but alpha raised to 0.85 and no backdrop filter.

## 8. Contrast results (computed, WCAG 2.x, worst-case backdrop = glass composited over brightest(dark)/darkest(light) bubble)

| theme | check | ratio |
|---|---|---|
| `blue` | Title/text on glass (worst backdrop) | **7.67** |
| `blue` | onGlassAccent on glass (worst) | **5.45** |
| `blue` | onGlassMuted on glass (worst) | **5.19** |
| `blue` | Sent-bubble text | **4.91** |
| `blue` | Received-bubble text | **11.74** |
| `blue` | Body text over wallpapered bg | **14.28** |
| `blue` | Date-pill text | **8.45** |
| `dark` | Title/text on glass (worst backdrop) | **11.1** |
| `dark` | onGlassAccent on glass (worst) | **5.34** |
| `dark` | onGlassMuted on glass (worst) | **7.15** |
| `dark` | Sent-bubble text | **8.44** |
| `dark` | Received-bubble text | **13.48** |
| `dark` | Body text over wallpapered bg | **15.96** |
| `dark` | Date-pill text | **8.25** |
| `light` | Title/text on glass (worst backdrop) | **14.67** |
| `light` | onGlassAccent on glass (worst) | **4.54** |
| `light` | onGlassMuted on glass (worst) | **6.14** |
| `light` | Sent-bubble text | **11.34** |
| `light` | Received-bubble text | **16.75** |
| `light` | Body text over wallpapered bg | **14.94** |
| `light` | Date-pill text | **4.71** |
| `teal` | Title/text on glass (worst backdrop) | **8.74** |
| `teal` | onGlassAccent on glass (worst) | **4.71** |
| `teal` | onGlassMuted on glass (worst) | **4.82** |
| `teal` | Sent-bubble text | **5.47** |
| `teal` | Received-bubble text | **17.49** |
| `teal` | Body text over wallpapered bg | **16.73** |
| `teal` | Date-pill text | **5.5** |

All ≥ 4.5:1. Computation script lives in the session eval history; recompute on any value change.

## 9. Implementation status (branch `feat/liquid-glass-redesign`)

| surface | status |
|---|---|
| Bottom nav pill + active capsule | GLASS (GlassBottomNav) |
| Tab header capsules (Chat/Contacts/Settings) | GLASS (MainTabScreenHeader) |
| Chat top bar capsules | GLASS (GlassTopBar) |
| Chat wallpaper (flame tile) | DONE (ChatBackgroundPattern) |
| Composer input pill | GLASS |
| Action-tile panel | GLASS (in-flow pill) |
| Bottom sheets (timer / contacts menu / anti-quantum) | GLASS (showGlassSheet) |
| GIF picker sheet | OPAQUE BY DESIGN (media-dense grid; §7 per-surface fallback) |
| Emoji picker panel | OPAQUE BY DESIGN (package-rendered dense grid; readability) |
| Reply/edit/timer banners | Rounded solid cards (content layer) |
| Date separators | Solid mini-pills (content layer) |
| Popup menus + alert dialogs | Rounded per-theme surfaces — NOT glass (framework-owned Material routes; treated as §7 fallback surfaces; true glass menus = possible follow-up, owner to ratify at PR review) |
| Settings tiles / auth screen | UNTOUCHED BY DESIGN (content surfaces; chrome above them is glassed) |
| Embedded desktop chat header | In-flow, solid (desktop pane header; glass floats only over scrollable content) |
