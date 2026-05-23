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
}
