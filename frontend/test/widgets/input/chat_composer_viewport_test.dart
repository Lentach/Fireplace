import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/input/chat_composer_viewport.dart';

void main() {
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
