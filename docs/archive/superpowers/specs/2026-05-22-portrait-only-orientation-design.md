# Portrait-Only Orientation — Design Spec

**Date:** 2026-05-22  
**Status:** Approved (product choices locked in chat)

---

## Problem Statement

Fireplace can be rotated to landscape on phones and tablets (native and web/PWA). In landscape, `MediaQuery.size.width` often exceeds `layoutBreakpointDesktop` (600 px), which switches the UI to the **desktop sidebar layout** on a device that is still a phone/tablet. Several features then misbehave. The PWA `manifest.json` already sets `"orientation": "portrait-primary"`, but **browsers ignore this in regular tabs** and it is not a reliable lock on all installed PWAs.

---

## Goal

- **Mobile + tablet (native Android/iOS and web/PWA):** App stays in **portrait up only**; user should not use landscape as the primary mode.
- **Desktop web (PC/Mac, wide window):** Unchanged — sidebar layout from 600 px width remains allowed; no rotate overlay on large screens.
- When landscape cannot be prevented, show a **blocking overlay** until the device returns to portrait.

---

## Product Decisions (Locked)

| Decision | Choice |
|----------|--------|
| Desktop browser layout | **A** — keep desktop layout when `width >= 600` on PC/Mac; orientation policy targets phones/tablets only. |
| Upside-down portrait | **No** — only `portraitUp` (choice **1**). |
| Landscape fallback UX | **A** — full-screen “Rotate your device” overlay (PL/EN via ARB), app not interactable underneath. |
| Overlay scope | Show when `orientation == landscape` **and** `shortestSide < 900` (phones + tablets; not typical PC monitor). |
| `manifest.json` `portrait-primary` | Keep as PWA hint; **do not rely on it alone**. |

---

## Root Cause (Technical)

`MainShell` and other screens use **width-only** desktop detection:

```dart
MediaQuery.sizeOf(context).width >= AppConstants.layoutBreakpointDesktop // 600
```

A phone in landscape (e.g. 844×390) has `width = 844` → desktop layout on a phone. Fixing orientation avoids this class of bugs without reworking responsive breakpoints in this change.

---

## Approaches Considered

### 1. Manifest / platform config only (rejected)

- Android `screenOrientation="portrait"`, iOS `Info.plist`, `manifest.json`.
- **Pros:** Simple, no Dart UI.
- **Cons:** Web tabs still rotate; iPad/split-screen edge cases; user confirmed manifest does not block rotation today.

### 2. Dart-only overlay, no platform lock (rejected)

- **Pros:** One code path for web + native.
- **Cons:** Native still rotates physically; brief broken UI before overlay; worse UX on Android/iOS.

### 3. Layered lock + overlay fallback (recommended — chosen)

| Layer | Mechanism |
|-------|-----------|
| Native hard lock | `SystemChrome.setPreferredOrientations([portraitUp])` + Android manifest + iOS plist |
| Web soft lock | Screen Orientation API `lock('portrait-primary')` where supported (best-effort, no user gesture required on some PWAs) |
| Universal fallback | `PortraitRequiredOverlay` when landscape + compact shortest side |

**Pros:** Best coverage; desktop unaffected; matches Telegram-style mobile apps.  
**Cons:** Web lock may silently fail — overlay covers that.

---

## Architecture

### Components

1. **`portrait_lock_policy.dart`** — pure functions: `shouldShowRotateOverlay(Size size, Orientation orientation)` (unit-tested).
2. **`portrait_lock_service.dart`** — applies `SystemChrome` on native; calls web bridge on `kIsWeb`; idempotent `initialize()`.
3. **`web_orientation_lock_web.dart` / `web_orientation_lock_stub.dart`** — conditional import; attempts `screen.orientation.lock('portrait-primary')`, swallows errors.
4. **`portrait_required_overlay.dart`** — modal full-screen UI (icon + localized title/body).
5. **`PortraitLockShell`** — wraps app via `MaterialApp.builder`; `Stack` of child + overlay when policy says so; listens to `MediaQuery` (rebuilds on rotate/resize).
6. **Platform files** — `AndroidManifest.xml`, `Info.plist` (portrait only).

### Integration point

`FireplaceApp` → `MaterialApp.builder`:

```dart
builder: (context, child) {
  return PortraitLockShell(child: child ?? const SizedBox.shrink());
},
```

`PortraitLockService.initialize()` called from `main()` after `WidgetsFlutterBinding.ensureInitialized()` (before `runApp`).

### Overlay detection (exact rule)

```dart
bool shouldShowRotateOverlay({
  required Orientation orientation,
  required Size logicalSize,
}) {
  if (orientation != Orientation.landscape) return false;
  return logicalSize.shortestSide < 900;
}
```

Constant `kPortraitLockMaxShortestSide = 900` in `app_constants.dart`.

**Examples:**

| Context | Size | Overlay? |
|---------|------|----------|
| Phone portrait | 390×844 | No |
| Phone landscape | 844×390 | Yes |
| iPad landscape | 1180×820 | Yes (shortest 820) |
| PC browser | 1920×1080 | No (shortest 1080) |
| Narrow desktop window | 700×500 landscape | Yes (shortest 500) — acceptable edge case |

### Localization (ARB)

| Key | EN (example) | PL (example) |
|-----|--------------|--------------|
| `rotateDeviceTitle` | Rotate your device | Obróć urządzenie |
| `rotateDeviceMessage` | Fireplace works in portrait mode only. | Fireplace działa tylko w trybie pionowym. |

Use `AppLocalizations` in overlay; follow existing `showTopSnackBar` / settings patterns.

### Web Orientation API notes

- May require **secure context** (HTTPS or localhost).
- Some browsers only allow lock in **installed PWA** or after fullscreen — failures are expected.
- **No permission prompt** — fire once at startup and optionally on `visibilitychange` → visible (mirror `MainShell` tab visibility pattern if needed in v1: startup only is enough).

### Native notes

- **Android:** `android:screenOrientation="portrait"` on `MainActivity` (strongest lock).
- **iOS:** `UISupportedInterfaceOrientations` = portrait only (iPhone + iPad); remove landscape entries.
- **SystemChrome:** `DeviceOrientation.portraitUp` only in `main()`; do not reset to all orientations on logout (single-activity app; avoids accidental unlock mid-session).

### Out of scope

- Changing `layoutBreakpointDesktop` or desktop responsive redesign.
- Forcing portrait on desktop browsers (user rejected).
- `SystemChrome` on web (unsupported).

---

## Testing

| Test | Type |
|------|------|
| `portrait_lock_policy_test.dart` | Unit: overlay true/false for size/orientation matrix |
| `portrait_required_overlay_test.dart` | Widget: shows localized strings with delegates |
| `fireplace_app_portrait_lock_test.dart` | Widget: `MaterialApp.builder` wraps `PortraitLockShell` |
| Manual | Android phone rotate, iOS phone, Chrome Android PWA, iPad landscape, PC browser wide window |

---

## Documentation

- Update `CLAUDE.md` § Frontend: portrait-only policy, overlay rule, platform files, why manifest alone is insufficient.

---

## Success Criteria

1. Android/iOS native app does not stay in landscape under normal use.
2. Web mobile/PWA: either locked to portrait or overlay blocks interaction in landscape.
3. PC browser at 1920×1080: no overlay; desktop sidebar still works.
4. `flutter test` and `flutter analyze` pass for new/changed files.
