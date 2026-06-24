import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/input/chat_composer_viewport.dart';
import 'package:fireplace/widgets/input/composer_keyboard_signals.dart';

void main() {
  tearDown(() => composerKeyboardCollapseGuard.value = false);

  testWidgets('applies list bottom padding at least composer height', (tester) async {
    double? capturedPadding;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatComposerViewport(
          messageListBuilder: (bottom) {
            capturedPadding = bottom;
            return ListView(
              reverse: true,
              padding: EdgeInsets.only(bottom: bottom),
              children: const [Text('msg')],
            );
          },
          composer: const SizedBox(
            height: 48,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedPadding, isNotNull);
    expect(capturedPadding!, greaterThanOrEqualTo(48));
  });

  testWidgets('increases list bottom padding when composer grows', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _GrowingComposerHarness()));
    await tester.pumpAndSettle();

    final listViewBefore = tester.widget<ListView>(find.byType(ListView));
    final paddingBefore = listViewBefore.padding as EdgeInsets;
    expect(paddingBefore.bottom, greaterThanOrEqualTo(48));

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    final listViewAfter = tester.widget<ListView>(find.byType(ListView));
    final paddingAfter = listViewAfter.padding as EdgeInsets;
    expect(paddingAfter.bottom, greaterThan(paddingBefore.bottom));
  });

  testWidgets('genuine dismiss collapses the keyboard inset immediately',
      (tester) async {
    composerKeyboardCollapseGuard.value = false;
    var padding = 0.0;
    await tester.pumpWidget(_insetHarness(300, onPadding: (p) => padding = p));
    await tester.pumpAndSettle();
    expect(padding, greaterThanOrEqualTo(48 + 300));

    await tester.pumpWidget(_insetHarness(0, onPadding: (p) => padding = p));
    await tester.pump(); // no timer wait — collapse must be immediate
    expect(padding, lessThan(48 + 300));
    expect(padding, greaterThanOrEqualTo(48));
  });

  testWidgets('send bounce defers the collapse for the debounce window',
      (tester) async {
    composerKeyboardCollapseGuard.value = true;
    var padding = 0.0;
    await tester.pumpWidget(_insetHarness(300, onPadding: (p) => padding = p));
    await tester.pumpAndSettle();
    expect(padding, greaterThanOrEqualTo(48 + 300));

    await tester.pumpWidget(_insetHarness(0, onPadding: (p) => padding = p));
    await tester.pump(const Duration(milliseconds: 100));
    expect(padding, greaterThanOrEqualTo(48 + 300)); // deferred: no drop/flash

    await tester.pump(const Duration(milliseconds: 500));
    expect(padding, lessThan(48 + 300)); // collapsed after the 450ms debounce
  });
}

class _GrowingComposerHarness extends StatefulWidget {
  const _GrowingComposerHarness();

  @override
  State<_GrowingComposerHarness> createState() => _GrowingComposerHarnessState();
}

class _GrowingComposerHarnessState extends State<_GrowingComposerHarness> {
  double _composerHeight = 48;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatComposerViewport(
        messageListBuilder: (bottom) => ListView(
          reverse: true,
          padding: EdgeInsets.only(bottom: bottom),
          children: const [Text('msg')],
        ),
        composer: SizedBox(
          height: _composerHeight,
          child: const ColoredBox(color: Colors.red),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _composerHeight = 120),
        child: const Icon(Icons.expand_more),
      ),
    );
  }
}

Widget _insetHarness(double inset, {required ValueChanged<double> onPadding}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
        child: Scaffold(
          // Production uses resizeToAvoidBottomInset:false so the composer
          // viewport owns the keyboard inset; default true would let Scaffold
          // consume the bottom inset before the viewport reads it.
          resizeToAvoidBottomInset: false,
          body: ChatComposerViewport(
            messageListBuilder: (bottom) {
              onPadding(bottom);
              return ListView(
                reverse: true,
                padding: EdgeInsets.only(bottom: bottom),
                children: const [Text('m')],
              );
            },
            composer: const SizedBox(
              height: 48,
              child: ColoredBox(color: Color(0xFFFF0000)),
            ),
          ),
        ),
      ),
    ),
  );
}
