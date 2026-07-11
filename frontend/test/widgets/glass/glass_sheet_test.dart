import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_sheet.dart';
import 'package:fireplace/widgets/glass/glass_surface.dart';

Widget _host({bool highContrast = false}) {
  // Modal routes build under the app-level MediaQuery, so device
  // accessibility flags must be injected via MaterialApp.builder.
  return MaterialApp(
    theme: RpgTheme.themeDataDarkGray,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast),
      child: child!,
    ),
    home: const Scaffold(body: _Opener()),
  );
}

class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        key: const ValueKey('open'),
        onPressed: () async {
          final result = await showGlassSheet<String>(
            context,
            builder: (ctx) => SizedBox(
              height: 200,
              child: Center(
                child: TextButton(
                  key: const ValueKey('pick'),
                  onPressed: () => Navigator.of(ctx).pop('picked'),
                  child: const Text('pick'),
                ),
              ),
            ),
          );
          if (context.mounted && result != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('got:$result')));
          }
        },
        child: const Text('open'),
      ),
    );
  }
}

void main() {
  testWidgets('opens a glass sheet over a transparent route and returns a '
      'result through pop', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    // Glass surface present, and the route's own material is transparent so
    // the blur actually samples the content behind the sheet.
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final sheetMaterials = tester
        .widgetList<Material>(find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        ))
        .toList();
    expect(sheetMaterials.first.color, Colors.transparent,
        reason: 'route material must not paint behind the glass');

    await tester.tap(find.byKey(const ValueKey('pick')));
    await tester.pumpAndSettle();
    expect(find.text('got:picked'), findsOneWidget,
        reason: 'sheet result must propagate through the helper');
  });

  testWidgets('opaque mode renders without a BackdropFilter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showGlassSheet<void>(
                context,
                opaque: true,
                builder: (_) => const SizedBox(height: 150),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('high-contrast forces the opaque fallback on sheets',
      (tester) async {
    await tester.pumpWidget(_host(highContrast: true));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('sheet dismisses by tapping the barrier', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsOneWidget);

    await tester.tapAt(const Offset(200, 50)); // barrier area
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsNothing);
  });
}
