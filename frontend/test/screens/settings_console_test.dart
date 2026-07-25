import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/settings_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/appearance_preview.dart';
import 'package:fireplace/widgets/local_node_core.dart';
import 'package:fireplace/widgets/settings_console.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _host({
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      theme: theme ?? RpgTheme.themeDataLight,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: const SettingsScreen(),
        ),
      ),
    ),
  );
}

void main() {
  group('Settings console', () {
    testWidgets('the local node is the shared core, not a bare avatar', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // The SAME widget the Contacts honeycomb core uses. If Settings ever
      // grows its own copy, the two drift and the tabs stop matching.
      expect(find.byType(LocalNodeCore), findsOneWidget);
      expect(find.text('LOCAL NODE'), findsOneWidget);
    });

    testWidgets('every section caption is upper-cased by the widget', (
      tester,
    ) async {
      // The Privacy screen reuses a screen TITLE as a caption
      // (`Privacy & Safety`) next to captions that come from already-caps
      // section keys (`SECURITY`), which put mixed casing on one rail. The
      // widget normalises so no call site can reintroduce it.
      await tester.pumpWidget(
        MaterialApp(
          theme: RpgTheme.themeDataLight,
          home: const Scaffold(
            body: SettingsSectionCaption(label: 'Privacy & Safety'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRIVACY & SAFETY'), findsOneWidget);
      expect(find.text('Privacy & Safety'), findsNothing);
    });

    testWidgets('the Appearance row previews the theme without clipping it', (
      tester,
    ) async {
      // Two owner-reported bugs live here, one per axis, both caused by
      // `_AppearancePreviewScene` using ABSOLUTE insets while only bubble
      // WIDTH scales with the box.
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final preview = tester.widget<AppearancePreview>(
        find.byType(AppearancePreview),
      );

      // WIDTH — the miniature was drawn at 92 and centre-cropped to the 38px
      // terminal to hide its own border, which threw away precisely the
      // `left: 8` / `right: 8` strips that carry both bubble colours:
      // "most of the hex is on background color with little visible chat
      // bubble". Matching the terminal keeps the scene whole sideways, and
      // dropping the border removes the reason the crop existed.
      expect(preview.width, kConsoleHexWidth);
      expect(
        preview.showBorder,
        isFalse,
        reason: 'the hex terminal already paints a ring',
      );

      // HEIGHT — shrinking to the terminal's own 44 slid the composer bar up
      // through the lower bubble and painted over it: "green/blue bubble is
      // covered by bottom block". The bar spans `height - 13 .. height - 6`,
      // so it clears the bubble only while that top stays below
      // kPreviewContentBottom. Asserted as the INVARIANT, not as a literal,
      // so retuning either the height or the scene's insets still fails
      // loudly instead of silently re-covering the bubble.
      expect(
        preview.height - kPreviewComposerBottom - kPreviewComposerHeight,
        greaterThanOrEqualTo(kPreviewContentBottom),
        reason: 'the composer bar overlaps the lower bubble',
      );
    });

    testWidgets('rows are console rows with no chevrons', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConsoleRow), findsWidgets);
      // The row IS the affordance. A chevron on every row was the Material
      // settings-list tell we removed.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('SECURITY'), findsOneWidget);

      // The ListView is lazy, so SESSION is not an element until it scrolls in.
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.text('SESSION'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('only the destructive row carries the filled wash', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      // Delete/Log out live in SESSION, below the fold of a lazy ListView.
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();

      final rows = tester
          .widgetList<SettingsConsoleRow>(find.byType(SettingsConsoleRow))
          .toList();
      final danger = rows
          .where((r) => r.edge == ConsoleRowEdge.danger)
          .toList();
      final accent = rows
          .where((r) => r.edge == ConsoleRowEdge.accent)
          .toList();

      // Exactly one destructive row (delete account). Log out is marked but
      // must NOT be washed: on the light themes `primary` is nearly the same
      // ember as `error`, so washing both merged them into one alarm block.
      expect(danger, hasLength(1));
      expect(accent, hasLength(1));

      Color? washOf(SettingsConsoleRow row) {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byWidget(row),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.decoration as BoxDecoration?)?.color;
      }

      expect(washOf(danger.single), isNotNull);
      expect(washOf(accent.single), isNull);
    });

    testWidgets('survives 320px at a 1.6 text scale without overflowing', (
      tester,
    ) async {
      // The language row's trailing chips are not flexible, so full language
      // names here used to crush the title into one letter per line. Same
      // viewport the Chats row-weight contracts are pinned at.
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(size: const Size(320, 700), textScale: 1.6),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PL'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
      // Not just "no overflow": a starved Expanded can wrap instead of
      // overflowing, which is the one-letter-per-line failure this test is
      // named for. Pin that the title still gets a usable line.
      expect(tester.getSize(find.text('Language')).width, greaterThan(80));
    });
  });
}
