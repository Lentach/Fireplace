import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_top_bar.dart';
import 'package:fireplace/widgets/top_snackbar.dart';

// Guards the fix for the toast covering the app-bar back arrow: the overlay must
// sit BELOW the GlassTopBar band, including the status-bar (notch) inset — not
// at top:0 where it hid the back arrow for the whole 2.5s duration.
//
// The inset is set at the WINDOW level (tester.view) so the root Overlay and the
// screen's SafeArea read the same padding, mirroring a real device.
void main() {
  testWidgets('top snackbar clears the back-arrow band', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 47); // iPhone notch
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataDarkGray,
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassTopBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {},
            ),
            title: const Text('Peer'),
          ),
          body: Builder(
            builder: (ctx) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showTopSnackBar(ctx, 'Anti-Quantum Note sent');
              });
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pump(); // run the post-frame callback + insert overlay
    await tester.pump();

    final arrowBottom = tester.getRect(find.byIcon(Icons.arrow_back)).bottom;
    final toastTop = tester.getRect(find.text('Anti-Quantum Note sent')).top;

    expect(
      toastTop,
      greaterThanOrEqualTo(arrowBottom),
      reason: 'toast ($toastTop) must not overlap back arrow ($arrowBottom)',
    );

    await tester.pump(const Duration(seconds: 3)); // let auto-dismiss fire
  });

  testWidgets(
    'default top snackbar remains non-interactive',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: RpgTheme.themeDataDarkGray,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showTopSnackBar(ctx, 'Plain notification');
                });
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Plain notification'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'action top snackbar invokes its callback and dismisses',
    (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: RpgTheme.themeDataDarkGray,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showTopSnackBar(
                    ctx,
                    'Invitation accepted',
                    actionLabel: 'Open chat',
                    onTap: () => taps += 1,
                  );
                });
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Open chat'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
        findsNothing,
      );

      await tester.tap(find.text('Open chat'));
      await tester.pump();

      expect(taps, 1);
      expect(find.text('Invitation accepted'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
    },
  );
}
