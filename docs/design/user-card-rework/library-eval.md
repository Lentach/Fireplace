# Fireplace Profile-Card — Flutter Library Evaluation

**Date:** 2026-07-15  
**Repo constraint:** `frontend/pubspec.yaml` → Dart SDK `^3.10.7` (Dart 3 required). Research only — no deps added.  
**Relevant existing deps:** `image_picker: ^1.2.3`, `file_picker: ^11.0.2`, `cross_file: ^0.3.4`, `web: ^1.1.0`, `google_fonts`, `provider`.  
**Hard requirement:** Flutter WEB / CanvasKit + iOS PWA is the primary device. Any package that is Dart-2-only or mobile-only is disqualified.

> Verdict key: web support is only "✅ verified" when pub.dev platform metadata *and* the package source/plugin registration confirm it. "Pure Dart" = no platform channel, so web is intrinsic.

---

## Need 1 — Avatar carousel/pager with segment indicator (Telegram-style)

**Goal:** swipe between up to 3 photos with a thin *segmented* indicator strip (equal-width bars, story-style), living inside a collapsing header.

| Candidate | Latest | SDK | Web | Maintenance | Fit |
|---|---|---|---|---|---|
| **Built-in `PageView`** | Flutter SDK | n/a | ✅ intrinsic | Framework | Ideal pager; 3 photos, cheap |
| **hand-rolled segment strip** (`Row` of `AnimatedContainer`) | — | — | ✅ | Yours | The only thing that gives a true *segment* bar |
| `smooth_page_indicator` | 2.0.1 | `>=3.0.0 <4.0.0` | ✅ (pub badge: web; pure-Dart CustomPaint) | Active (2.0.1, changelog Feb-2025; 4.1k likes) | Great for **dots**, not segments |
| `carousel_slider` | 5.1.2 | `>=2.12.0 <4.0.0` | ✅ (PageView wrapper, pure Dart) | Active-ish (5.1.2, Feb-2026); fork `carousel_slider_plus` more active | Overkill; adds no segment indicator |

**Web-support verdict:** all ✅. `PageView` is framework. `smooth_page_indicator` lists web on pub.dev and is pure `CustomPaint`. `carousel_slider` is a thin pure-Dart wrapper over `PageView`. Sources: https://pub.dev/packages/smooth_page_indicator (platforms Android/iOS/Linux/macOS/**web**/Windows), https://pub.dev/packages/carousel_slider.

**Maintenance verdict:** `smooth_page_indicator` 2.0.1 healthy (SDK Dart-3, active issues, 4.1k likes). `carousel_slider` 5.1.2 maintained but slower cadence — community has partly migrated to `carousel_slider_plus`.

**Key gotcha — PageView inside `SliverAppBar.flexibleSpace` (verified from Flutter GitHub):**
- **#41157 — "PageView inside a FlexibleSpaceBar doesn'\''t keep its state."** Swiping to photo 2/3, then scrolling vertically to collapse the app bar, resets the PageView back to page 1. This is the single most relevant bug for this exact layout. https://github.com/flutter/flutter/issues/41157
- **#62273 — "PageView starts UNDER SliverAppBar in a NestedScrollView rather than BELOW it."** Layout/overlap when a PageView is used as flexibleSpace background inside NestedScrollView. https://github.com/flutter/flutter/issues/62273
- Related, non-blocking context: #155602 (AppBar scrolled-under state when scroll is inside PageView) https://github.com/flutter/flutter/issues/155602 ; #19254 (SliverAppBar stops scrolling when another scrollable is added) https://github.com/flutter/flutter/issues/19254 .
- **Why it happens:** `CustomScrollView` shares one vertical `Scrollable` across slivers. A horizontal `PageView` coexists because the axes differ — but `FlexibleSpaceBar` rebuilds its background as `shrinkOffset` changes, and a fresh `PageController`/rebuild drops page state (#41157).
- **Mitigations that work:** hoist the `PageController` to a `State` above the sliver (never recreate it in the delegate/background builder); add `AutomaticKeepAliveClientMixin` to pages; prefer placing the carousel in a **`SliverPersistentHeader` custom delegate** (see Need 3) rather than `FlexibleSpaceBar.background`, so you own the rebuild and don'\''t inherit FlexibleSpaceBar'\''s parallax/reset behavior.

**Recommendation:** **Built-in `PageView` + a hand-rolled segment strip (~30 lines: `Row` of `Expanded`→`AnimatedContainer`), driven by a hoisted `PageController`.** No dependency earns its place: `smooth_page_indicator` only draws dots (Telegram/story UX is equal-width *bars*, which it cannot render), and `carousel_slider` adds a `PageView` wrapper you don'\''t need for 3 images. If product later accepts a dot indicator, add `smooth_page_indicator` 2.0.1 (`ScrollingDotsEffect`/`ExpandingDotsEffect`) — it is the best-maintained, web-clean option. Place the pager in the Need-3 `SliverPersistentHeader` delegate to sidestep #41157/#62273.

---

## Need 2 — Image picking + cropping for avatar (square/circle), WEB + iOS PWA mandatory

App already has `image_picker: ^1.2.3` (web-capable) — reuse it for picking; only the **cropper** is in question.

| Candidate | Latest | SDK | Web | Maintenance | Notes |
|---|---|---|---|---|---|
| **`crop_your_image`** | 2.0.0 | `>=3.0.0 <4.0.0` | ✅ pure Dart (`image` pkg only, no platform channel) | Moderate (2.0.0; last major ~2024–25) | You build the crop UI; circle/square via `withCircleUi`/`aspectRatio` |
| `image_cropper` | 12.2.1 | `>=3.3.0 <4.0.0` | ⚠️ yes, but via JS `cropperjs` + index.html script tags | Active (12.2.1, 2026) | Native uCrop/TOCrop on mobile; separate web impl |
| `custom_image_crop` | 0.1.1 | `>=2.12.0 <4.0.0` | ✅ pure Dart (gesture_x_detector, vector_math) | Low (0.1.1, Dec-2024, icapps) | Works on web but immature (v0.1.x) |

**Web-support verdict:**
- `crop_your_image` **✅ verified**: depends only on `flutter` + `image: ^4.3.0` (pure Dart), no platform channel → web is intrinsic. https://pub.dev/packages/crop_your_image (deps show only `image`).
- `image_cropper` **⚠️ verified-with-caveats**: web works, but through the federated plugin `image_cropper_for_web` which injects **cropperjs** (CDN `cropperjs/1.6.2` `<link>`/`<script>` must be added to `web/index.html`). The web implementation differs from mobile and some fields (e.g. `compressQuality`) are no-ops on web. Sources: https://pub.dev/packages/image_cropper (deps: `image_cropper_for_web: ^7.0.0`), changelog documenting the cropperjs CDN tags, and https://pub.dev/documentation/image_cropper/latest/ ("implementation on Web is much different… compressQuality not working").
- `custom_image_crop` **✅ (by construction)** pure Dart, but v0.1.1 maturity is a risk for a production avatar flow.

**Maintenance verdict:** `image_cropper` most actively maintained (12.2.1, 2026) and most popular, but its web path is a JS-interop bolt-on requiring index.html edits — friction on a CanvasKit/iOS-PWA target. `crop_your_image` 2.0.0 is healthy enough and pure-Dart (one rendering path across web + iOS). `custom_image_crop` 0.1.1 too immature.

**Recommendation:** **`crop_your_image` 2.0.0.** For an iOS-PWA-first, CanvasKit app you want one code path that renders identically on web and mobile with no `index.html` JS injection and no platform-channel surprises. It gives circle/square crop out of the box (`withCircleUi: true`, `aspectRatio: 1`) and composes cleanly with the existing `image_picker` → `XFile`/bytes flow. `image_cropper` is the fallback only if you need native uCrop/TOCrop polish on mobile and accept maintaining the cropperjs `<script>` tags for web.

---

## Need 3 — Collapsing sliver header: full-bleed photo → circular avatar on scroll

| Candidate | Latest | SDK | Web | Maintenance | Fit |
|---|---|---|---|---|---|
| **Built-in `SliverPersistentHeader` + custom `SliverPersistentHeaderDelegate`** | Flutter SDK | n/a | ✅ intrinsic | Framework | Exactly this problem; `shrinkOffset` lerps full-bleed→circle |
| `SliverAppBar` + `FlexibleSpaceBar` | Flutter SDK | n/a | ✅ | Framework | Easy collapse, but fights the PageView (see #41157) and can'\''t cleanly morph to a circle |
| `sliver_tools` | 0.2.12 | `>=2.12.0 <4.0.0` | ✅ | **Stale — last release ~July 2023 (~2 yrs)** | Grouping/pinned helpers; no collapsing-avatar |
| `extended_sliver` | 2.1.3 | **`>=2.12.0 <3.0.0`** | ✅ | **DISQUALIFIED — Dart-2 only** | `ExtendedSliverAppbar` exists but SDK excludes Dart 3 |

**Web-support verdict:** all ✅ (framework slivers + pure-Dart packages all list web). But `extended_sliver` 2.1.3 caps SDK at `<3.0.0` — **it will not resolve against this repo'\''s `^3.10.7`** (source: https://pub.dev/packages/extended_sliver, SDK `>=2.12.0 <3.0.0`). Hard fail regardless of features.

**Maintenance verdict:** `sliver_tools` 0.2.12 last released ~2 years ago (https://pub.dev/packages/sliver_tools) — usable but stale, and it offers `MultiSliver`/`SliverPinnedHeader`, **not** a collapsing-avatar. `extended_sliver` is effectively dead for Dart 3. Neither provides the circle-morph you need.

**Recommendation:** **No package — built-in `SliverPersistentHeader` with a custom delegate (~80–120 lines).** Override `minExtent`/`maxExtent`, read `shrinkOffset`, compute `t = (shrinkOffset / (maxExtent - minExtent)).clamp(0,1)`, and `lerp` the photo'\''s size, border-radius (full-bleed → circle), position, and opacity of overlaid text. This is the canonical Flutter solution for the Telegram collapse, has zero dependency/maintenance risk, is fully web/CanvasKit-safe, and is where you should also host the Need-1 `PageView` (hoisted `PageController`) to avoid the `FlexibleSpaceBar` state-reset bug #41157. A package does **not** earn its place here: the only Dart-3-compatible option (`sliver_tools`) doesn'\''t do the morph, and the one that hints at it (`extended_sliver`) is incompatible.

---

## Summary of single recommendations

1. **Carousel + segment strip:** built-in `PageView` + hand-rolled segment `Row` (no dep). `smooth_page_indicator` 2.0.1 only if dots are acceptable.
2. **Crop:** `crop_your_image` 2.0.0 (pure Dart, one path for web + iOS PWA). Reuse existing `image_picker` for picking.
3. **Collapsing avatar header:** built-in `SliverPersistentHeader` custom delegate (no dep). `extended_sliver` disqualified (Dart-2 only); `sliver_tools` stale and off-target.

**Net new dependencies recommended:** at most **one** (`crop_your_image`), and zero if an existing/custom crop path is acceptable. Needs 1 and 3 are best solved with the framework.
