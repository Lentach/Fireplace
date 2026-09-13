// The bubble BODY renders through `TextMessageContent._displayBody`, which
// since 0.2.43 delegates to the shared `sentinelDisplayText` — the same
// mapping `messageDisplayContent` uses, so the two surfaces can no longer
// disagree (they did: live QA 2026-08-31 saw the body print a sentinel raw
// while the long-press replica localized it). This file pins the body path
// itself, which is what a user actually reads.
// The pre-link sentinel no longer reaches a bubble at all — amendment (lxxxi)
// hides those rows at `MessagingProvider.messages`.

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart'
    show kRetiredMessageLabel;
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
  testWidgets('the retired marker keeps its localized mapping', (tester) async {
    final pl = await AppLocalizations.delegate.load(const Locale('pl'));
    await tester.pumpWidget(_host(_msg(kRetiredMessageLabel)));
    await tester.pumpAndSettle();

    expect(find.textContaining(pl.messageNoLongerStoredOnThisDevice, findRichText: true),
        findsOneWidget);
  });
}
