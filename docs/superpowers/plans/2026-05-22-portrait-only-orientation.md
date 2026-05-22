# Portrait-Only Orientation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock Fireplace to portrait-up on phones and tablets (native + web/PWA), with a blocking rotate overlay when landscape still occurs; keep desktop web layout unchanged on wide screens.

**Architecture:** Three layers — platform manifest/plist + `SystemChrome` on native, best-effort Screen Orientation API on web, and a `PortraitLockShell` wrapping `MaterialApp` that shows `PortraitRequiredOverlay` when `orientation == landscape` and `shortestSide < 900`. Policy logic is pure Dart and unit-tested.

**Tech stack:** Flutter 3.x, `flutter/services.dart` (`SystemChrome`), conditional-import web bridge (`package:web` + `dart:js_interop`, matching `web_push_bridge_web.dart` style), ARB l10n.

**Spec:** `docs/superpowers/specs/2026-05-22-portrait-only-orientation-design.md`

---

### Task 1: Policy constant + unit tests

**Files:**
- Modify: `frontend/lib/constants/app_constants.dart`
- Create: `frontend/lib/utils/portrait_lock_policy.dart`
- Create: `frontend/test/utils/portrait_lock_policy_test.dart`

- [ ] **Step 1: Add constant**

In `app_constants.dart`:

```dart
/// Shortest logical side below this → show rotate overlay in landscape (phones/tablets).
static const double portraitLockMaxShortestSide = 900;
```

- [ ] **Step 2: Add policy helper**

Create `portrait_lock_policy.dart`:

```dart
import 'package:flutter/widgets.dart';
import '../constants/app_constants.dart';

bool shouldShowRotateOverlay({
  required Orientation orientation,
  required Size logicalSize,
}) {
  if (orientation != Orientation.landscape) return false;
  return logicalSize.shortestSide <
      AppConstants.portraitLockMaxShortestSide;
}
```

- [ ] **Step 3: Write tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/portrait_lock_policy.dart';

void main() {
  test('portrait never shows overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.portrait,
        logicalSize: const Size(390, 844),
      ),
      isFalse,
    );
  });

  test('phone landscape shows overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.landscape,
        logicalSize: const Size(844, 390),
      ),
      isTrue,
    );
  });

  test('desktop landscape does not show overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.landscape,
        logicalSize: const Size(1920, 1080),
      ),
      isFalse,
    );
  });

  test('iPad landscape shows overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.landscape,
        logicalSize: const Size(1180, 820),
      ),
      isTrue,
    );
  });
}
```

- [ ] **Step 4: Run tests**

Run: `cd frontend && flutter test test/utils/portrait_lock_policy_test.dart`  
Expected: PASS

---

### Task 2: Native + web lock services

**Files:**
- Create: `frontend/lib/services/portrait_lock_service.dart`
- Create: `frontend/lib/services/web_orientation_lock_stub.dart`
- Create: `frontend/lib/services/web_orientation_lock_web.dart`

- [ ] **Step 1: Web stub**

`web_orientation_lock_stub.dart`:

```dart
Future<void> lockPortraitPrimaryIfSupported() async {}
```

- [ ] **Step 2: Web implementation**

`web_orientation_lock_web.dart` — use `package:web` / `dart:js_interop` (same style as `web_push_bridge_web.dart`):

```dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> lockPortraitPrimaryIfSupported() async {
  final screen = web.window.screen;
  if (screen == null) return;
  final orientation = screen.orientation;
  if (orientation == null) return;
  try {
    await orientation.lock('portrait-primary'.toJS).toDart;
  } catch (_) {
    // Unsupported, denied, or not installed PWA — overlay handles UX.
  }
}
```

Export via conditional import in `portrait_lock_service.dart`:

```dart
import 'web_orientation_lock_stub.dart'
    if (dart.library.html) 'web_orientation_lock_web.dart' as web_orientation;
```

- [ ] **Step 3: Portrait lock service**

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'web_orientation_lock_stub.dart'
    if (dart.library.html) 'web_orientation_lock_web.dart' as web_orientation;

class PortraitLockService {
  PortraitLockService._();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) {
      await web_orientation.lockPortraitPrimaryIfSupported();
      return;
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  /// Re-attempt web lock after tab becomes visible (optional hardening).
  static Future<void> reapplyWebLockIfNeeded() async {
    if (!kIsWeb) return;
    await web_orientation.lockPortraitPrimaryIfSupported();
  }
}
```

- [ ] **Step 4: Call from main**

Modify `frontend/lib/main.dart`:

```dart
import 'services/portrait_lock_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PortraitLockService.initialize();
  // ... existing Firebase / file_picker / runApp
}
```

---

### Task 3: Rotate overlay widget + widget test

**Files:**
- Modify: `frontend/lib/l10n/app_en.arb`
- Modify: `frontend/lib/l10n/app_pl.arb`
- Create: `frontend/lib/widgets/portrait_required_overlay.dart`
- Create: `frontend/test/widgets/portrait_required_overlay_test.dart`

- [ ] **Step 1: ARB strings**

`app_en.arb`:

```json
"rotateDeviceTitle": "Rotate your device",
"@rotateDeviceTitle": { "description": "Shown when app is used in landscape on phones/tablets" },
"rotateDeviceMessage": "Fireplace works in portrait mode only.",
"@rotateDeviceMessage": { "description": "Body under rotateDeviceTitle" },
```

`app_pl.arb`:

```json
"rotateDeviceTitle": "Obróć urządzenie",
"rotateDeviceMessage": "Fireplace działa tylko w trybie pionowym.",
```

Run: `cd frontend && flutter gen-l10n` (or `flutter pub get` if gen runs on build).

- [ ] **Step 2: Overlay widget**

```dart
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class PortraitRequiredOverlay extends StatelessWidget {
  const PortraitRequiredOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.screen_rotation_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.rotateDeviceTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.rotateDeviceMessage,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/widgets/portrait_required_overlay.dart';

void main() {
  testWidgets('shows localized rotate message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pl'),
        home: const PortraitRequiredOverlay(),
      ),
    );
    expect(find.text('Obróć urządzenie'), findsOneWidget);
    expect(find.textContaining('trybie pionowym'), findsOneWidget);
  });
}
```

Run: `cd frontend && flutter test test/widgets/portrait_required_overlay_test.dart`

---

### Task 4: PortraitLockShell + wire MaterialApp

**Files:**
- Create: `frontend/lib/widgets/portrait_lock_shell.dart`
- Modify: `frontend/lib/main.dart` (`FireplaceApp`)
- Create: `frontend/test/main/fireplace_app_portrait_lock_test.dart`

- [ ] **Step 1: Shell widget**

```dart
import 'package:flutter/material.dart';
import '../utils/portrait_lock_policy.dart';
import 'portrait_required_overlay.dart';

class PortraitLockShell extends StatelessWidget {
  const PortraitLockShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final showOverlay = shouldShowRotateOverlay(
      orientation: mq.orientation,
      logicalSize: mq.size,
    );
    if (!showOverlay) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Positioned.fill(
          child: AbsorbPointer(child: PortraitRequiredOverlay()),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: MaterialApp.builder**

In `FireplaceApp` `MaterialApp`:

```dart
builder: (context, child) {
  return PortraitLockShell(
    child: child ?? const SizedBox.shrink(),
  );
},
```

- [ ] **Step 3: Regression test**

Mirror `fireplace_app_scroll_behavior_test.dart` — pump `FireplaceApp` or minimal `MaterialApp` with same `builder` and assert `PortraitLockShell` exists (use `find.byType(PortraitLockShell)`).

- [ ] **Step 4: Run**

`cd frontend && flutter test test/main/fireplace_app_portrait_lock_test.dart`

---

### Task 5: Platform manifests

**Files:**
- Modify: `frontend/android/app/src/main/AndroidManifest.xml`
- Modify: `frontend/ios/Runner/Info.plist`

- [ ] **Step 1: Android**

On `<activity android:name=".MainActivity" ...>` add:

```xml
android:screenOrientation="portrait"
```

Keep existing `configChanges` (Flutter still handles in-process rotation events; lock prevents user rotation).

- [ ] **Step 2: iOS iPhone**

Replace `UISupportedInterfaceOrientations` array with only:

```xml
<string>UIInterfaceOrientationPortrait</string>
```

- [ ] **Step 3: iOS iPad**

Replace `UISupportedInterfaceOrientations~ipad` with only:

```xml
<string>UIInterfaceOrientationPortrait</string>
```

Remove `PortraitUpsideDown`, `LandscapeLeft`, `LandscapeRight`.

- [ ] **Step 4: Manual smoke**

- Android emulator: rotate hardware — app stays portrait or shows overlay briefly.
- `flutter run -d chrome` with DevTools device toolbar → landscape → overlay visible, portrait → gone.
- Desktop Chrome wide window → no overlay.

---

### Task 6: Optional web visibility re-lock

**Files:**
- Modify: `frontend/lib/screens/main_shell.dart` (web tab visibility block only)

- [ ] On `visibilitychange` → visible (`kIsWeb`), call `PortraitLockService.reapplyWebLockIfNeeded()` (fire-and-forget `.ignore()`). Skip if scope too large — **YAGNI:** omit in v1 unless manual test shows PWA loses lock after backgrounding.

---

### Task 7: CLAUDE.md + graphify + verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] Add § Frontend bullet: portrait-only (`PortraitLockService`, `PortraitLockShell`, overlay threshold 900, manifest hint insufficient, desktop web exempt).
- [ ] Run: `graphify update .`
- [ ] Run: `cd frontend && flutter analyze`
- [ ] Run: `cd frontend && flutter test`

---

## Manual test checklist

- [ ] Android phone/emulator: cannot use app in landscape (or overlay blocks).
- [ ] iOS simulator/device: same.
- [ ] Chrome Android — installed PWA + tab: landscape blocked or overlay.
- [ ] PC browser 1920×1080: desktop sidebar, no overlay.
- [ ] Chat composer still works in portrait after change (no regression).

---

## Execution handoff

**Plan saved to:** `docs/superpowers/plans/2026-05-22-portrait-only-orientation.md`  
**Spec saved to:** `docs/superpowers/specs/2026-05-22-portrait-only-orientation-design.md`
