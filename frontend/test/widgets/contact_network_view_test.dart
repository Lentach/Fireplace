import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/contact_network_view.dart';

UserModel _contact(int id, String name) =>
    UserModel(id: id, username: name, tag: '0001');

List<ContactNetworkLayoutInput> _inputs(int count) => [
  for (var i = 0; i < count; i++)
    ContactNetworkLayoutInput(
      id: i + 1,
      displayName: 'user${i + 1}',
      labelSize: const Size(64, 14),
    ),
];

Widget _host(
  Widget child, {
  Size size = const Size(390, 700),
  bool disableAnimations = true,
}) {
  return MaterialApp(
    theme: RpgTheme.themeDataDarkGray,
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ContactNetworkLayout', () {
    test('identical inputs produce identical layouts', () {
      const viewport = Size(366, 600);
      const localLabel = Size(70, 12);
      final a = ContactNetworkLayout.resolve(
        contacts: _inputs(8),
        safeViewport: viewport,
        localLabelSize: localLabel,
        savedPins: const {},
      );
      final b = ContactNetworkLayout.resolve(
        contacts: _inputs(8),
        safeViewport: viewport,
        localLabelSize: localLabel,
        savedPins: const {},
      );
      expect(a.localCenter, b.localCenter);
      expect(a.contactCenters, b.contactCenters);
      expect(a.ringExtents, b.ringExtents);
    });

    test('contacts never overlap the local node visual rect', () {
      final layout = ContactNetworkLayout.resolve(
        contacts: _inputs(8),
        safeViewport: const Size(366, 600),
        localLabelSize: const Size(70, 12),
        savedPins: const {},
      );
      final localRect = Rect.fromLTWH(
        layout.localCenter.dx - layout.metrics.localVisualWidth / 2,
        layout.localCenter.dy - layout.metrics.localNodeRadius,
        layout.metrics.localVisualWidth,
        ContactNetworkLayoutMetrics.localNodeDiameter +
            ContactNetworkLayoutMetrics.labelGap +
            layout.metrics.localLabelSize.height,
      );
      layout.contactCenters.forEach((id, center) {
        final rect = layout.metrics.visualRectFor(
          layout.inputById[id]!,
          center,
        );
        expect(
          rect.overlaps(localRect),
          isFalse,
          reason: 'contact $id overlaps the local node',
        );
      });
    });

    test('contact visual rects never overlap pairwise', () {
      final scenarios = <(int, Size, Size)>[
        // Fitted phone layout.
        (8, const Size(366, 600), const Size(64, 14)),
        // Long labels / accessibility text scale.
        (12, const Size(366, 600), const Size(150, 24)),
        // Dense interactive (pannable) layout.
        (25, const Size(320, 480), const Size(64, 14)),
      ];
      for (final (count, viewport, labelSize) in scenarios) {
        final layout = ContactNetworkLayout.resolve(
          contacts: [
            for (var i = 0; i < count; i++)
              ContactNetworkLayoutInput(
                id: i + 1,
                displayName: 'user${i + 1}',
                labelSize: labelSize,
              ),
          ],
          safeViewport: viewport,
          localLabelSize: const Size(70, 12),
          savedPins: const {},
        );
        final rects = [
          for (final entry in layout.contactCenters.entries)
            layout.metrics.visualRectFor(
              layout.inputById[entry.key]!,
              entry.value,
            ),
        ];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].deflate(0.5).overlaps(rects[j].deflate(0.5)),
              isFalse,
              reason:
                  'nodes $i and $j overlap in scenario '
                  '($count contacts, $viewport, $labelSize)',
            );
          }
        }
      }
    });

    test('saved pins are hints: out-of-bounds pins are clamped inside', () {
      final layout = ContactNetworkLayout.resolve(
        contacts: _inputs(3),
        safeViewport: const Size(366, 600),
        localLabelSize: const Size(70, 12),
        // Normalized coords far outside the 0..1 range.
        savedPins: const {1: Offset(9.0, -4.0)},
      );
      final center = layout.contactCenters[1]!;
      final bounds = layout.metrics.centerBoundsFor(layout.inputById[1]!);
      expect(center.dx, inInclusiveRange(bounds.left, bounds.right));
      expect(center.dy, inInclusiveRange(bounds.top, bounds.bottom));
    });

    test('every contact keeps a 48dp hit-target node at the floor', () {
      final layout = ContactNetworkLayout.resolve(
        contacts: _inputs(40),
        safeViewport: const Size(320, 480),
        localLabelSize: const Size(70, 12),
        savedPins: const {},
      );
      expect(
        layout.metrics.nodeDiameter,
        greaterThanOrEqualTo(ContactNetworkLayoutMetrics.nodeFloorDiameter),
      );
      expect(layout.usesInteractiveViewer, isTrue);
    });
  });

  group('ContactNetworkView', () {
    testWidgets('tapping a node opens that contact', (tester) async {
      UserModel? tapped;
      await tester.pumpWidget(
        _host(
          ContactNetworkView(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            localNodeLabel: 'marta',
            localNodeCaption: 'LOCAL NODE',
            emptyTitle: 'empty',
            emptyMessage: 'add friends',
            onContactTap: (user) => tapped = user,
            networkSemanticLabel: 'network',
            localNodeSemanticLabel: 'you',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ada'));
      await tester.pump();
      expect(tapped?.id, 1);
    });

    testWidgets(
      'reduce motion: tap routes synchronously without pulse delay',
      (tester) async {
        UserModel? tapped;
        await tester.pumpWidget(
          _host(
            ContactNetworkView(
              contacts: [_contact(1, 'ada')],
              localNodeLabel: 'marta',
              localNodeCaption: 'LOCAL NODE',
              emptyTitle: 'empty',
              emptyMessage: 'add friends',
              onContactTap: (user) => tapped = user,
              networkSemanticLabel: 'network',
              localNodeSemanticLabel: 'you',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('ada'));
        // No pump: with disableAnimations the callback fires in the tap
        // handler itself instead of after the 180ms pulse.
        expect(tapped?.id, 1);
      },
    );

    testWidgets('nodes are semantic buttons labeled with the username', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          ContactNetworkView(
            contacts: [_contact(1, 'ada')],
            localNodeLabel: 'marta',
            localNodeCaption: 'LOCAL NODE',
            emptyTitle: 'empty',
            emptyMessage: 'add friends',
            onContactTap: (_) {},
            networkSemanticLabel: 'network',
            localNodeSemanticLabel: 'you',
          ),
        ),
      );
      await tester.pumpAndSettle();

      SemanticsNode? target;
      void visit(SemanticsNode node) {
        if (node.label == 'ada') {
          target = node;
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(
        tester.binding.renderViews.first.owner!.semanticsOwner!
            .rootSemanticsNode!,
      );
      expect(target, isNotNull, reason: 'no semantics node labeled ada');
      final data = target!.getSemanticsData();
      expect(data.label, 'ada');
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('keyboard: Enter on a focused node opens the contact', (
      tester,
    ) async {
      UserModel? tapped;
      await tester.pumpWidget(
        _host(
          ContactNetworkView(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            localNodeLabel: 'marta',
            localNodeCaption: 'LOCAL NODE',
            emptyTitle: 'empty',
            emptyMessage: 'add friends',
            onContactTap: (user) => tapped = user,
            networkSemanticLabel: 'network',
            localNodeSemanticLabel: 'you',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // Traversal order is the sorted contact order, so the first Tab stop
      // is 'ada'.
      expect(tapped?.id, 1);
    });

    testWidgets(
      'keyboard focus reveals an initially offscreen node in the pannable map',
      (tester) async {
        // 25 contacts in a small viewport forces the InteractiveViewer path
        // with a map larger than the screen.
        final contacts = [
          for (var i = 1; i <= 25; i++) _contact(i, 'user${i.toString().padLeft(2, '0')}'),
        ];
        await tester.pumpWidget(
          _host(
            ContactNetworkView(
              contacts: contacts,
              localNodeLabel: 'marta',
              localNodeCaption: 'LOCAL NODE',
              emptyTitle: 'empty',
              emptyMessage: 'add friends',
              onContactTap: (_) {},
              networkSemanticLabel: 'network',
              localNodeSemanticLabel: 'you',
            ),
            size: const Size(320, 480),
          ),
        );
        await tester.pumpAndSettle();

        // Tab through every node; the traversal order matches the sorted
        // contact order, ending on the last contact.
        for (var i = 0; i < contacts.length; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        final label = find.text('user25');
        expect(label, findsOneWidget);
        final rect = tester.getRect(label);
        // The host widget is centered inside the 800x600 test surface, so
        // the viewport rect must be taken from the widget itself.
        final viewport = tester.getRect(find.byType(ContactNetworkView));
        // The focused node's label must have been panned into the viewport.
        // Full containment: the reveal contract is the whole label visible,
        // not one pixel overlapping.
        expect(
          viewport.contains(rect.topLeft) &&
              viewport.contains(rect.bottomRight),
          isTrue,
          reason:
              'focused node not fully revealed: $rect outside $viewport',
        );
      },
    );
  });
}
