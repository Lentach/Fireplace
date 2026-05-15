---
inclusion: manual
---

# Frontend Design (ported to Kiro steering)

Kiro-port of the [Frontend Design](https://claude.com/plugins/frontend-design) plugin (Anthropic). Pull it in with `#frontend-design.md` when you're building or redesigning UI and want output that doesn't look like generic AI slop.

> Fireplace's UI is Flutter (Material 3 + `FireplaceColors` ThemeExtension + `AppScrollBehavior`). All guidance below applies to Flutter widgets and Dart, and separately to any web (HTML/CSS) surface. If both directions contradict, follow the Flutter side for this repo.

## Why this skill exists

Default AI frontend output tends to:

- Reach for system fonts (`-apple-system`, `Roboto`) without thinking.
- Default to purple/blue gradients, rounded-2xl cards, Tailwind grey-on-white.
- Use the same landing-page shape every time (hero → 3-col features → testimonial → CTA).
- Avoid animation, depth, rhythm, negative space.
- Treat every product the same, regardless of audience.

This skill forces an explicit design-first pass before any widget or JSX is written.

## Workflow

### Step 1. Design brief (before any code)

Produce a short brief — 6 to 10 bullet points, shown to the user for sign-off:

- **Purpose** — one sentence, what the surface actually does.
- **Audience** — who uses it, what tools they already use, what "good" looks like to them.
- **Emotional goal** — pick 2–3 adjectives (e.g. "calm, confident, technical"; "playful, generous, loud").
- **Aesthetic direction** — choose one, name it:
  - Brutalist (raw, monospaced, black/white, sharp corners, visible grid)
  - Editorial (serif display, long measure, asymmetric layout, hairline rules)
  - Retro-futuristic (CRT textures, neon, scanlines, monospaced metadata)
  - Luxury (tight typography, deep darks, gold/ivory, generous air)
  - Playful (rounded, high-saturation, hand-drawn accents, micro-animations)
  - Maximalist (stacked cards, overlapping elements, heavy color blocking)
  - System/ops (dense tables, mono fonts, inline status, minimal chrome)
  - Custom — name it and describe.
- **Forbidden patterns** — state what we are *not* doing (e.g. "no purple-blue gradient hero", "no 3-column feature grid", "no stock illustration").
- **Motion budget** — none / subtle (hover only) / expressive (scroll + entrance) / heavy (parallax, physics).
- **Density** — sparse / balanced / dense.
- **Device priority** — mobile-first / desktop-first / PWA / responsive parity.

No code yet. Wait for user to approve or edit.

### Step 2. Design system pass

Before writing the screen, define tokens. For Flutter, wire them into `FireplaceColors` + `ThemeExtension` where possible; for web, define CSS custom properties. Produce:

- **Typography pair** — one display / one body. Don't reach for Inter + Roboto by default. Consider: *serif + mono* (editorial/technical), *grotesque + condensed display* (brutalist), *humanist sans + italic serif* (warm), *monospace across the board* (ops, dev tools). Specify weights and sizes as a scale (e.g. 12/14/16/20/28/44/64), not ad-hoc.
- **Color palette** — 1 base, 1 surface, 1 accent, 1 critical, plus 2 neutrals. State each as a concrete hex. Avoid the default indigo-500 + slate-700 combo unless it's genuinely chosen.
- **Spacing scale** — 4/8/12/16/24/32/48/64 (or a deliberate alternative; e.g. golden-ratio 4/6/10/16/26/42).
- **Radius scale** — consistent, not per-component guesses. Zero radius is a valid choice.
- **Elevation / depth** — pick a strategy: shadows, layered gradients, borders-only, printed-paper feel. Don't mix.
- **Iconography** — one family; specify stroke width and corner style.

### Step 3. Layout moves (pick at least two)

Generic layouts happen when no deliberate spatial decision is made. Commit to at least two of:

- **Asymmetry** — offset columns, uneven splits (62/38 instead of 50/50), intentional blank quadrants.
- **Grid-breaking** — a heading or image escapes the content column.
- **Rhythm** — alternating row colors, vertical beats, repeating motifs.
- **Negative space** — a section whose job is to breathe.
- **Overlap / layering** — cards that cross the fold of a hero, text over image with controlled contrast.
- **Rotation / skew** — controlled, not decorative-only; ties into brand (e.g. a tilted card grid).
- **Edge-to-edge vs centered content** — decide which blocks bleed full-width.

### Step 4. Motion plan

Scale to the motion budget from Step 1.

- **Subtle** — hover/active states, focus ring animations, `Hero` transitions on navigation, implicit `AnimatedSwitcher` on state change.
- **Expressive** — entrance staggers for lists (`flutter_staggered_animations` pattern or manual `AnimationController`), scroll-triggered reveals (`SliverAppBar` + `FlexibleSpaceBar` or IntersectionObserver on web), shared-element transitions between screens.
- **Heavy** — physics-based drag, parallax, canvas/Rive, scroll-linked timelines.

Rules:

- Every animation has a reason (direct attention, confirm state, reinforce hierarchy). If you can't state the reason in a sentence, cut it.
- Respect reduced-motion. On web: `@media (prefers-reduced-motion: reduce)`. On Flutter: `MediaQuery.of(context).disableAnimations`.
- Duration: 150–250ms for state, 300–450ms for transitions, >600ms only for staged reveals.
- Easing: don't ship `Curves.linear` or `ease`. Pick deliberately — `Curves.easeOutCubic` for entrance, `Curves.easeInOutQuart` for large movements, custom cubics for brand.

### Step 5. Detail pass (the part most AI output skips)

Before you declare done, add at least three of:

- Custom focus ring that matches the aesthetic (not browser default).
- Non-default selection color.
- Empty state with actual content — illustration, one-line guidance, primary action.
- Loading state that isn't a bare spinner — skeleton, shimmer, staged placeholder.
- Error state with recovery action, not just a red toast.
- Hover/pressed micro-state (scale 0.98, color shift, border bloom).
- Unexpected flourish that ties to the brief — a pull-quote style, a stamped timestamp, a marginal note, a subtle grain texture, a rotating accent, a single emoji used consistently.
- Text set with proper measure (45–75 chars) and hanging punctuation where it reads better.

### Step 6. Accessibility (non-negotiable)

Never trade this for aesthetics.

- Contrast: body text ≥ 4.5:1, large text / UI ≥ 3:1. Verify with actual hex pairs, not vibes.
- Tap targets ≥ 44x44 logical px (Flutter default is often smaller — wrap `IconButton` or use `InkWell` with `minSize`).
- Focus order follows reading order; visible focus indicator on every interactive element.
- Semantic widgets: `Semantics(label: ...)`, `ExcludeSemantics` for pure decoration, `MergeSemantics` for label+control pairs. On web, real `<button>`, `<a href>`, heading order.
- Keyboard paths: every primary action reachable and operable from keyboard alone.
- Motion respects reduced-motion preference.
- Color is never the only carrier of meaning (icons + text labels for status).
- Localization: no hardcoded English in widgets — use `AppLocalizations` with keys in `app_en.arb` / `app_pl.arb` (Fireplace convention).

### Step 7. Output

When delivering code:

- Lead with the design brief (Step 1) and token set (Step 2) as a short readable block at the top of the response.
- Then deliver the widget / component, with tokens referenced by name, not by inline magic values.
- Note which detail-pass items (Step 5) are implemented.
- Flag anything the user should review: font licensing, asset delivery, motion budget mismatch, brand alignment.

## Forbidden patterns (for this skill)

When `#frontend-design.md` is active, do not produce any of the following without an explicit justification:

- Purple-to-blue gradient hero background.
- Default `Inter` or `Roboto` without a considered alternative.
- Three-column "features" grid with icon-title-paragraph cards.
- `rounded-2xl` cards with `shadow-lg` on white — the signature ChatGPT-era landing shape.
- Stock illustrations (Undraw, Pablo, Humaaans) unless the brief explicitly calls for them.
- Generic testimonial card with circular avatar + gray 5-star row.
- Tailwind `slate-*` on `white` with no accent.
- Centered hero + CTA + fade-in-up, no other motion.
- Emoji as iconography unless the brief explicitly asks for it.

## Flutter-specific notes (Fireplace)

- Wire colors through `FireplaceColors` ThemeExtension — `SettingsScreen` and related tests already depend on it. Local `Color(0xFF…)` inline is a smell outside `theme/`.
- Respect `AppScrollBehavior` (`theme/app_scroll_behavior.dart`) — do not opt back into `StretchingOverscrollIndicator` per-screen.
- Use `showTopSnackBar()` for user notifications, not `ScaffoldMessenger` (covered by chat input bar).
- Bottom bars and composers: mind system insets (see `CLAUDE.md` — `SafeArea(bottom: false)` at screen level, composer reads `viewPadding.bottom`).
- Any animation controller created in a `State` must be disposed. Test with `flutter analyze` before committing.
- On web, test against Chrome; verify `patch_webcrypto_16k.ps1` is not needed for your change path.
- Widget tests using `AppLocalizations` must pass `localizationsDelegates` + `supportedLocales` — otherwise `AppLocalizations.of(context)` returns null.

## Quick prompts (what triggers this skill)

- "Design a <screen> for <audience>."
- "Redesign the <screen> — it feels generic."
- "Build a landing page / dashboard / settings panel for <product>."
- "Pick a visual direction for <feature>, then implement it."

When the user's prompt is short ("make the settings screen nicer"), still produce Step 1's brief — don't skip straight to code.
