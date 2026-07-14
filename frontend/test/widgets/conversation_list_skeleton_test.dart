import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/conversation_list_skeleton.dart';

Widget _host({required bool reduceMotion, ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? RpgTheme.themeDataDarkGray,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const Scaffold(
        body: ConversationListSkeleton(padding: EdgeInsets.all(8), rowCount: 5),
      ),
    ),
  );
}

Finder _skeletonizer() => find.byWidgetPredicate((w) => w is Skeletonizer);

Skeletonizer _skeletonizerOf(WidgetTester tester) =>
    tester.widget(_skeletonizer()) as Skeletonizer;

void main() {
  testWidgets('renders a Skeletonizer over the requested rows', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: false));
    await tester.pump(); // let one shimmer frame settle

    expect(find.byType(ConversationListSkeleton), findsOneWidget);
    expect(_skeletonizer(), findsOneWidget);
  });

  testWidgets('uses an animated ShimmerEffect when motion is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(reduceMotion: false));
    await tester.pump();

    expect(_skeletonizerOf(tester).effect, isA<ShimmerEffect>());
  });

  testWidgets('falls back to a static SolidColorEffect under reduce-motion', (
    tester,
  ) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pump();

    expect(_skeletonizerOf(tester).effect, isA<SolidColorEffect>());
  });

  testWidgets('renders without error in a light theme', (tester) async {
    await tester.pumpWidget(
      _host(reduceMotion: false, theme: RpgTheme.themeDataLight),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_skeletonizer(), findsOneWidget);
  });
}
