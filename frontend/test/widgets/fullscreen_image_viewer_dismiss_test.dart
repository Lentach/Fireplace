import 'package:fireplace/widgets/media/fullscreen_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner report 2026-09-14: a swipe down dismissed a fullscreen VIDEO but did
/// nothing on a still image or GIF. `frontend/docs/composer-media.md` requires
/// a green repro for anything in this area, so this is it — the drag path, and
/// the zoom hand-off that makes it safe.
///
/// The zoom case is the one that would break a user: if the dismiss recognizer
/// stayed armed while zoomed in, panning a magnified photo would throw the
/// viewer away mid-inspection.
void main() {
  Future<void> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: EdgeInsets.zero,
                    child: FullscreenImageViewer(
                      image: Container(color: Colors.red),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenImageViewer), findsOneWidget);
  }

  testWidgets('a swipe down dismisses the viewer', (tester) async {
    await openViewer(tester);

    // Past the 0.22-of-viewport threshold, released slowly (no fling).
    await tester.drag(find.byType(FullscreenImageViewer), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.byType(FullscreenImageViewer), findsNothing);
  });

  testWidgets('a downward fling dismisses even on a short travel', (
    tester,
  ) async {
    await openViewer(tester);

    await tester.fling(
      find.byType(FullscreenImageViewer),
      const Offset(0, 60),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullscreenImageViewer), findsNothing);
  });

  testWidgets('a short slow drag snaps back and keeps the viewer', (
    tester,
  ) async {
    await openViewer(tester);

    await tester.drag(find.byType(FullscreenImageViewer), const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(find.byType(FullscreenImageViewer), findsOneWidget);
  });

  testWidgets('an upward drag never dismisses', (tester) async {
    await openViewer(tester);

    await tester.drag(
      find.byType(FullscreenImageViewer),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullscreenImageViewer), findsOneWidget);
  });

  testWidgets('while zoomed in, dragging pans instead of dismissing', (
    tester,
  ) async {
    await openViewer(tester);

    // Pinch out: two pointers moving apart. This is what arms panning and
    // disarms the dismiss drag.
    final center = tester.getCenter(find.byType(FullscreenImageViewer));
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0));
    await a.moveBy(const Offset(-120, 0));
    await b.moveBy(const Offset(120, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(FullscreenImageViewer), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.byType(FullscreenImageViewer), findsOneWidget);
  });
}
