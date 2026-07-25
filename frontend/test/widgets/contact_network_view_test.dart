import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/contact_network_view.dart';
import 'package:fireplace/widgets/hex_avatar.dart';

UserModel _contact(int id, String name, {String? avatar}) =>
    UserModel(id: id, username: name, tag: '0001', profilePictureUrl: avatar);

List<ContactHexLayoutInput> _inputs(int count) => [
  for (var i = 0; i < count; i++)
    ContactHexLayoutInput(id: i + 1, displayName: 'user${i + 1}'),
];

ContactHexLayoutResult _resolve(
  int count, {
  double width = 366,
  double labelHeight = 15,
}) => ContactHexLayout.resolve(
  contacts: _inputs(count),
  width: width,
  labelHeight: labelHeight,
);

Widget _host(
  Widget child, {
  Size size = const Size(390, 700),
  bool disableAnimations = true,
}) {
  return MaterialApp(
    theme: RpgTheme.themeDataDarkGray,
    home: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

ContactNetworkView _view({
  required List<UserModel> contacts,
  ValueChanged<UserModel>? onTap,
  ValueChanged<UserModel>? onOpenChat,
  Set<int> conversationIds = const {},
}) {
  return ContactNetworkView(
    contacts: contacts,
    localNodeLabel: 'Marta',
    localNodeCaption: 'LOCAL NODE',
    emptyTitle: 'No contacts yet',
    emptyMessage: 'Add friends to start',
    onContactTap: onTap ?? (_) {},
    onContactOpenChat: onOpenChat,
    networkSemanticLabel: 'Contact network',
    localNodeSemanticLabel: 'You, local node',
    conversationContactIds: conversationIds,
  );
}

void main() {
  group('ContactHexLayout', () {
    test('identical inputs produce identical slots', () {
      final a = _resolve(27);
      final b = _resolve(27);
      expect(a.slots, b.slots);
      expect(a.rowOf, b.rowOf);
      expect(a.coreCenter, b.coreCenter);
      expect(a.fieldHeight, b.fieldHeight);
    });

    test('slot order is the natural sort of display names', () {
      final layout = ContactHexLayout.resolve(
        contacts: const [
          ContactHexLayoutInput(id: 1, displayName: 'ziomek50'),
          ContactHexLayoutInput(id: 2, displayName: 'Ada'),
          ContactHexLayoutInput(id: 3, displayName: 'ziomek3'),
          ContactHexLayoutInput(id: 4, displayName: 'borys'),
        ],
        width: 366,
        labelHeight: 15,
      );
      expect(layout.inputs.map((c) => c.displayName).toList(), [
        'Ada',
        'borys',
        'ziomek3',
        'ziomek50',
      ]);
    });

    test('no two slot visual rects overlap at any tested geometry', () {
      for (final count in [3, 8, 15, 27, 40]) {
        for (final width in [296.0, 366.0, 1076.0]) {
          for (final labelHeight in [15.0, 24.0]) {
            final layout = _resolve(
              count,
              width: width,
              labelHeight: labelHeight,
            );
            for (var i = 0; i < count; i++) {
              for (var j = i + 1; j < count; j++) {
                final a = layout.visualRectAt(i);
                final b = layout.visualRectAt(j);
                final overlap = a.intersect(b);
                expect(
                  overlap.width <= 0.01 || overlap.height <= 0.01,
                  isTrue,
                  reason:
                      'slots $i/$j overlap at count=$count width=$width '
                      'labelHeight=$labelHeight: $a vs $b',
                );
              }
            }
          }
        }
      }
    });

    test('every slot rect stays inside the field width', () {
      for (final width in [296.0, 366.0, 1076.0]) {
        final layout = _resolve(27, width: width);
        for (var i = 0; i < 27; i++) {
          final rect = layout.visualRectAt(i);
          expect(rect.left, greaterThanOrEqualTo(-0.01), reason: 'i=$i');
          expect(
            rect.right,
            lessThanOrEqualTo(width + 0.01),
            reason: 'i=$i width=$width',
          );
        }
      }
    });

    test('rows fill 4-3-4-3 and the partial last row centers itself', () {
      final layout = _resolve(9);
      expect(layout.rowOf, [0, 0, 0, 0, 1, 1, 1, 2, 2]);
      // Last row holds 2: centered as a symmetric pair around the core x.
      final lastRow = [layout.slots[7].dx, layout.slots[8].dx];
      final center = layout.coreCenter.dx;
      expect(lastRow[0] - center, closeTo(-(lastRow[1] - center), 0.001));
    });

    test('hex hit target clears the 48dp floor', () {
      expect(ContactHexLayout.hexRadius * 2, greaterThanOrEqualTo(48));
      expect(ContactHexLayout.hexWidth, greaterThanOrEqualTo(48));
    });

    test('field height grows with count and width never changes it', () {
      final small = _resolve(8);
      final large = _resolve(40);
      expect(large.fieldHeight, greaterThan(small.fieldHeight));
      // More contacts never widen the field: slots stay within the same
      // horizontal envelope regardless of count.
      final envelope27 = _resolve(
        27,
      ).slots.map((s) => s.dx).reduce((a, b) => a > b ? a : b);
      final envelope40 = _resolve(
        40,
      ).slots.map((s) => s.dx).reduce((a, b) => a > b ? a : b);
      expect(envelope40, envelope27);
    });

    test('route path stays inside the field horizontal bounds', () {
      final layout = _resolve(27);
      for (final index in [0, 5, 12, 26]) {
        final bounds = ContactHexLayout.routePath(layout, index).getBounds();
        expect(bounds.left, greaterThanOrEqualTo(-0.01));
        expect(bounds.right, lessThanOrEqualTo(366.01));
        // The route ends at the target's socket pad.
        final slot = layout.slots[index];
        expect(
          bounds.bottom,
          closeTo(slot.dy - ContactHexLayout.hexRadius - 9, 0.01),
        );
      }
    });
  });

  group('ContactNetworkView', () {
    testWidgets('renders a semantic button per contact with username', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          _view(
            contacts: [
              _contact(1, 'ada'),
              _contact(2, 'borys'),
              _contact(3, 'celina'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final name in ['ada', 'borys', 'celina']) {
        expect(find.bySemanticsLabel(name), findsOneWidget);
      }
      expect(find.bySemanticsLabel('You, local node'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('local core is drawn on the field axis, not beside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _view(contacts: [for (var i = 1; i <= 8; i++) _contact(i, 'user$i')]),
        ),
      );
      await tester.pumpAndSettle();

      // The caption is wider than the reticle. When the core's Positioned
      // shrink-wrapped the Column, that width pushed the avatar off
      // `layout.coreCenter` - the exact point every feed line is aimed at -
      // and the leftmost first-row wires stopped short of the rim.
      final field = tester.getRect(find.byType(ContactNetworkView));
      final core = tester.getRect(
        find.ancestor(
          of: find.byType(HexAvatarSurface),
          matching: find.byType(ClipOval),
        ),
      );
      expect(core.center.dx, closeTo(field.center.dx, 0.5));
      expect(
        tester.getRect(find.text('LOCAL NODE')).center.dx,
        closeTo(field.center.dx, 0.5),
      );
    });

    testWidgets('tap opens contact synchronously under reduce motion', (
      tester,
    ) async {
      UserModel? tapped;
      await tester.pumpWidget(
        _host(
          _view(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            onTap: (user) => tapped = user,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ada'));
      expect(tapped?.username, 'ada');
    });

    testWidgets('animated tap fills the route before opening the card', (
      tester,
    ) async {
      UserModel? tapped;
      await tester.pumpWidget(
        _host(
          _view(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            onTap: (user) => tapped = user,
          ),
          disableAnimations: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('borys'));
      await tester.pump();
      // Mid-flight: the route strip is still travelling to the core.
      await tester.pump(const Duration(milliseconds: 250));
      expect(tapped, isNull);
      // Docked: the card opens.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tapped?.username, 'borys');
      await tester.pumpAndSettle();
    });

    testWidgets('the route fill repaints without rebuilding the nodes', (
      tester,
    ) async {
      // The route controller drives one painter. It used to drive the whole
      // Stack, so every frame of the 480ms fill rebuilt every contact node
      // (Focus + Semantics + GestureDetector + ClipPath + Image apiece) -
      // ~6k subtree builds per tap on a 100-contact board. Widget identity
      // across fill frames is the cheapest honest proof that is not
      // happening: a rebuilt subtree hands back a new Widget instance.
      await tester.pumpWidget(
        _host(
          _view(
            contacts: [for (var i = 1; i <= 12; i++) _contact(i, 'user$i')],
          ),
          disableAnimations: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('user7'));
      await tester.pump();
      final atStart = tester.widget<Text>(find.text('user3'));

      await tester.pump(const Duration(milliseconds: 150));
      expect(
        identical(tester.widget<Text>(find.text('user3')), atStart),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        identical(tester.widget<Text>(find.text('user3')), atStart),
        isTrue,
      );

      await tester.pumpAndSettle();
    });

    testWidgets('long press on a wired contact opens the chat directly', (
      tester,
    ) async {
      UserModel? carded;
      UserModel? chatted;
      await tester.pumpWidget(
        _host(
          _view(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            onTap: (user) => carded = user,
            onOpenChat: (user) => chatted = user,
            conversationIds: const {2},
          ),
          disableAnimations: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('borys'));
      await tester.pump();

      // Straight in: no route animation in front of the chat route.
      expect(chatted?.username, 'borys');
      expect(carded, isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('long press without a conversation cannot start one', (
      tester,
    ) async {
      UserModel? chatted;
      await tester.pumpWidget(
        _host(
          _view(
            contacts: [_contact(1, 'ada')],
            onOpenChat: (user) => chatted = user,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('ada'));
      await tester.pumpAndSettle();

      expect(chatted, isNull);
    });

    testWidgets('wired nodes expose a long-press action with its meaning', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          ContactNetworkView(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            localNodeLabel: 'Marta',
            localNodeCaption: 'LOCAL NODE',
            emptyTitle: 'No contacts yet',
            emptyMessage: 'Add friends to start',
            onContactTap: (_) {},
            onContactOpenChat: (_) {},
            openChatSemanticHint: 'Open chat',
            networkSemanticLabel: 'Contact network',
            localNodeSemanticLabel: 'You, local node',
            conversationContactIds: const {2},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('borys')),
        matchesSemantics(
          label: 'borys',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
          onLongPressHint: 'Open chat',
        ),
      );
      // A contact with no wire keeps tap-only semantics.
      expect(
        tester.getSemantics(find.bySemanticsLabel('ada')),
        matchesSemantics(label: 'ada', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('the add cell heads the field, never a fake contact', (
      tester,
    ) async {
      var addTapped = 0;
      await tester.pumpWidget(
        _host(
          ContactNetworkView(
            contacts: [_contact(1, 'ada'), _contact(2, 'borys')],
            localNodeLabel: 'Marta',
            localNodeCaption: 'LOCAL NODE',
            emptyTitle: 'No contacts yet',
            emptyMessage: 'Add friends to start',
            onContactTap: (_) {},
            onAddContact: () => addTapped++,
            addSlotLabel: 'add',
            networkSemanticLabel: 'Contact network',
            localNodeSemanticLabel: 'You, local node',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
      expect(addTapped, 1);

      // Reachable without scrolling: it is the first cell of the first row,
      // not the tail of the alphabet seven rows down.
      expect(
        tester.getRect(find.text('add')).left,
        lessThan(tester.getRect(find.text('ada')).left),
      );
      expect(
        tester.getRect(find.text('add')).center.dy,
        closeTo(tester.getRect(find.text('ada')).center.dy, 0.5),
      );

      // Reserved as geometry only: the contact list the layout reports is
      // still just the real people.
      final layout = ContactHexLayout.resolve(
        contacts: _inputs(2),
        width: 366,
        labelHeight: 15,
        leadingSlots: 1,
      );
      expect(layout.inputs, hasLength(2));
      expect(layout.slots, hasLength(3));
      expect(layout.leadingSlots, 1);
    });

    testWidgets('an empty account still offers the add cell', (tester) async {
      await tester.pumpWidget(
        _host(
          ContactNetworkView(
            contacts: const [],
            localNodeLabel: 'Marta',
            localNodeCaption: 'LOCAL NODE',
            emptyTitle: 'No contacts yet',
            emptyMessage: 'Add friends to start',
            onContactTap: (_) {},
            onAddContact: () {},
            addSlotLabel: 'add',
            networkSemanticLabel: 'Contact network',
            localNodeSemanticLabel: 'You, local node',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('add'), findsOneWidget);
      // The copy moves below the cell instead of colliding with it.
      expect(find.text('No contacts yet'), findsOneWidget);
      expect(
        tester.getRect(find.text('No contacts yet')).top,
        greaterThan(tester.getRect(find.text('add')).bottom),
      );
    });

    testWidgets('the inbound port only exists when requests are waiting', (
      tester,
    ) async {
      var portTapped = 0;
      Widget view({required int pending}) => ContactNetworkView(
        contacts: [_contact(1, 'ada')],
        localNodeLabel: 'Marta',
        localNodeCaption: 'LOCAL NODE',
        emptyTitle: 'No contacts yet',
        emptyMessage: 'Add friends to start',
        onContactTap: (_) {},
        pendingRequestCount: pending,
        onPendingRequestsTap: () => portTapped++,
        pendingRequestsSemanticLabel: '$pending friend requests waiting',
        networkSemanticLabel: 'Contact network',
        localNodeSemanticLabel: 'You, local node',
      );

      await tester.pumpWidget(_host(view(pending: 0)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.south), findsNothing);

      await tester.pumpWidget(_host(view(pending: 3)));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.south));
      await tester.pumpAndSettle();
      expect(portTapped, 1);
    });
    testWidgets('keyboard focus reveals deep nodes by scrolling', (
      tester,
    ) async {
      final contacts = [
        for (var i = 0; i < 40; i++) _contact(i + 1, 'user${i + 1}'),
      ];
      await tester.pumpWidget(
        _host(_view(contacts: contacts), size: const Size(390, 700)),
      );
      await tester.pumpAndSettle();

      // Tab to the last node in traversal order (user40).
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.text('user40'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(700));

      // Enter activates the focused node.
      UserModel? opened;
      await tester.pumpWidget(
        _host(
          _view(contacts: contacts, onTap: (u) => opened = u),
          size: const Size(390, 700),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened?.username, 'user40');
    });

    testWidgets('avatars below the fold do not fetch until scrolled to', (
      tester,
    ) async {
      final contacts = [
        for (var i = 1; i <= 60; i++)
          _contact(i, 'user$i', avatar: 'https://example.test/$i.png'),
      ];
      await tester.pumpWidget(
        _host(_view(contacts: contacts), size: const Size(390, 700)),
      );
      await tester.pumpAndSettle();

      int armed() => tester
          .widgetList<HexAvatarSurface>(find.byType(HexAvatarSurface))
          .where((surface) => surface.imageUrl != null)
          .length;

      // Every node is built - focus and semantics still reach all 60 - but
      // only the rows on screen are allowed to pull a face.
      expect(find.byType(HexAvatarSurface), findsNWidgets(61)); // + the core
      final onMount = armed();
      expect(onMount, greaterThan(0));
      expect(onMount, lessThan(60));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final afterScroll = armed();
      expect(afterScroll, greaterThan(onMount));

      // Scrolling back must not drop already-loaded faces to initials.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();
      expect(armed(), afterScroll);
    });

    testWidgets('empty contact set shows the empty copy and the core', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_view(contacts: const [])));
      await tester.pumpAndSettle();

      expect(find.text('No contacts yet'), findsOneWidget);
      expect(find.text('Add friends to start'), findsOneWidget);
      expect(find.text('LOCAL NODE'), findsOneWidget);
    });

    testWidgets('field scrolls when contacts outgrow the viewport', (
      tester,
    ) async {
      final contacts = [
        for (var i = 0; i < 40; i++) _contact(i + 1, 'user${i + 1}'),
      ];
      await tester.pumpWidget(
        _host(_view(contacts: contacts), size: const Size(390, 700)),
      );
      await tester.pumpAndSettle();
      // The last contact starts below the fold (it exists in the tree; the
      // field is not lazy)...
      expect(tester.getRect(find.text('user40')).top, greaterThan(700));
      // ...and scrolls into the viewport.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.text('user40'));
      expect(rect.bottom, lessThanOrEqualTo(700));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(find.text('user40'), findsOneWidget);
    });
  });
}
