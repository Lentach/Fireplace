// Live QA 2026-08-31: a re-linked device rendered the §5.3 none_for_device
// marker as the RAW '[Sent before this device was linked]' sentinel — English
// brackets in a Polish UI. `messageDisplayContent` maps every sentinel, but
// the bubble BODY renders through `TextMessageContent._displayBody`, which
// mapped only the retired one. This file pins the body path itself.

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart'
    show kNotLinkedYetMessageLabel, kRetiredMessageLabel;
import 'package:fireplace/widgets/message/text_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg(String content) => MessageModel(
  id: 1,
  content: content,
  senderId: 2,
  senderUsername: 'bob',
  conversationId: 10,
  createdAt: DateTime.utc(2026, 1, 1),
);

Widget _host(MessageModel m, {Locale locale = const Locale('pl')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TextMessageContent(
          message: m,
          isMine: false,
          textColor: Colors.black,
          isDark: false,
          maxWidth: 300,
        ),
      ),
    );

void main() {
  testWidgets('the §5.3 not-linked marker renders localized, never the raw '
      'sentinel', (tester) async {
    final pl = await AppLocalizations.delegate.load(const Locale('pl'));
    await tester.pumpWidget(_host(_msg(kNotLinkedYetMessageLabel)));
    await tester.pumpAndSettle();

    expect(find.textContaining(pl.messageSentBeforeDeviceLinked, findRichText: true),
        findsOneWidget);
    expect(find.textContaining(kNotLinkedYetMessageLabel, findRichText: true), findsNothing,
        reason: 'raw sentinel text must never reach the user');
  });

  testWidgets('the retired marker keeps its localized mapping', (tester) async {
    final pl = await AppLocalizations.delegate.load(const Locale('pl'));
    await tester.pumpWidget(_host(_msg(kRetiredMessageLabel)));
    await tester.pumpAndSettle();

    expect(find.textContaining(pl.messageNoLongerStoredOnThisDevice, findRichText: true),
        findsOneWidget);
  });
}
