import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/text_message_content.dart';

MessageModel _msg(String content) => MessageModel(
  id: 1,
  conversationId: 1,
  senderId: 37,
  senderUsername: 'bob',
  content: content,
  messageType: MessageType.text,
  createdAt: DateTime.now(),
);

Widget _wrap(MessageModel m) => MaterialApp(
  theme: RpgTheme.themeDataDarkGray,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: TextMessageContent(
          message: m,
          isMine: false,
          textColor: Colors.white,
          isDark: true,
          maxWidth: 250,
        ),
      ),
    ),
  ),
);

void main() {
  final longText = List.generate(60, (i) => 'log line number $i').join('\n');

  testWidgets('short message shows no Read more toggle', (tester) async {
    await tester.pumpWidget(_wrap(_msg('hi there, short message')));
    expect(find.text('Read more'), findsNothing);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets('long message collapses behind Read more then expands',
      (tester) async {
    await tester.pumpWidget(_wrap(_msg(longText)));

    // Collapsed: toggle present, body clipped to the collapse cap.
    expect(find.text('Read more'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);
    final collapsed = tester.getSize(find.byType(RichText).first).height;

    await tester.ensureVisible(find.text('Read more'));
    await tester.tap(find.text('Read more'));
    await tester.pump();

    // Expanded: full text taller, toggle flips to Show less.
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Read more'), findsNothing);
    final expanded = tester.getSize(find.byType(RichText).first).height;
    expect(expanded, greaterThan(collapsed));

    // Collapse again.
    await tester.ensureVisible(find.text('Show less'));
    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(find.text('Read more'), findsOneWidget);
  });
}
