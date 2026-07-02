import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/pinned_message_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PinnedMessageBanner(
            previewText: 'Hello',
            senderLabel: 'alice',
            onTap: () => tapped = true,
            onUnpin: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PinnedMessageBanner));
    expect(tapped, isTrue);
  });

  testWidgets('unpin button fires onUnpin, not onTap', (tester) async {
    var tapped = false;
    var unpinned = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PinnedMessageBanner(
            previewText: 'Hello',
            senderLabel: 'alice',
            onTap: () => tapped = true,
            onUnpin: () => unpinned++,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    expect(unpinned, 1);
    expect(tapped, isFalse,
        reason: 'the embedded unpin button must not bubble into banner onTap');
  });

  testWidgets('renders senderLabel and previewText with ellipsis overflow',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PinnedMessageBanner(
            previewText: 'a very long pinned preview that cannot possibly fit',
            senderLabel: 'alice',
            onTap: () {},
            onUnpin: () {},
          ),
        ),
      ),
    );

    expect(find.text('alice'), findsOneWidget);
    final preview = tester.widget<Text>(
      find.text('a very long pinned preview that cannot possibly fit'),
    );
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);
  });
}
