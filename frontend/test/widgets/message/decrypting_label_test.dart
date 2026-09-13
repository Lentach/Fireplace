import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/text_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cold chat entry must Signal-decrypt every row before it can show anything,
/// which takes SECONDS on a full page. Rendering the raw "[encrypted]" sentinel
/// for that whole window made a normal wait look like a failure — the reported
/// symptom was "every message was encrypted for 3-5 seconds, then turned into
/// text".
///
/// The relabel is deliberately narrow, because getting it wrong is worse than
/// the original complaint: a terminal failure disguised as a spinner never
/// resolves, and keyed media legitimately keeps the sentinel forever.
MessageModel _msg({
  required String content,
  String? encryptedContent,
}) => MessageModel(
  id: 1,
  conversationId: 1,
  senderId: 37,
  senderUsername: 'bob',
  content: content,
  encryptedContent: encryptedContent,
  messageType: MessageType.text,
  createdAt: DateTime.now(),
);

Widget _wrap(
  MessageModel m, {
  required bool decrypting,
  bool isMine = false,
}) => MaterialApp(
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
          isMine: isMine,
          textColor: Colors.white,
          isDark: true,
          maxWidth: 250,
          decryptInProgress: decrypting,
        ),
      ),
    ),
  ),
);

/// The body is built from InlineSpans, so the finder has to descend into
/// RichText — without this it silently matches nothing and every assertion
/// below would pass vacuously.
Finder _body(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('a row awaiting decryption reads as decrypting, not encrypted',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _msg(content: '[encrypted]', encryptedContent: '2:abc'),
        decrypting: true,
      ),
    );

    expect(_body('Decrypting'), findsOneWidget);
    expect(_body('[encrypted]'), findsNothing);
  });

  testWidgets('once the pass ends the row falls back to the real sentinel',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _msg(content: '[encrypted]', encryptedContent: '2:abc'),
        decrypting: false,
      ),
    );

    expect(
      _body('[encrypted]'),
      findsOneWidget,
      reason:
          'a row still unresolved after the pass must not keep claiming to be '
          'working on it',
    );
    expect(_body('Decrypting'), findsNothing);
  });

  testWidgets('a terminal failure is never disguised as in-progress',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _msg(content: '[Decryption failed]', encryptedContent: '2:abc'),
        decrypting: true,
      ),
    );

    expect(
      _body('Decrypting'),
      findsNothing,
      reason: 'terminal means terminal — a spinner here would never resolve',
    );
    expect(
      _body("can't be read on this device"),
      findsOneWidget,
      reason:
          'the user gets the reason, not the internal sentinel; the row is '
          'still terminal, only the wording changed',
    );
  });

  testWidgets('already-decrypted text is untouched mid-pass', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _msg(content: 'hello there', encryptedContent: '2:abc'),
        decrypting: true,
      ),
    );

    expect(_body('hello there'), findsOneWidget);
    expect(_body('Decrypting'), findsNothing);
  });

  testWidgets('a row with no ciphertext is never relabelled', (tester) async {
    await tester.pumpWidget(
      _wrap(_msg(content: '[encrypted]'), decrypting: true),
    );

    expect(
      _body('[encrypted]'),
      findsOneWidget,
      reason:
          'displayAsEncryptedPlaceholder requires ciphertext; without it there '
          'is nothing being decrypted',
    );
  });

  testWidgets('a terminally failed row explains itself instead of leaking the '
      'sentinel', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _msg(content: '[Decryption failed]', encryptedContent: '2:abc'),
        decrypting: false,
      ),
    );

    expect(_body("can't be read on this device"), findsOneWidget);
    expect(
      _body('[Decryption failed]'),
      findsNothing,
      reason: 'this is the string the user reported as looking like a crash',
    );
  });

  testWidgets('an own row whose plaintext died with the cache explains itself',
      (tester) async {
    // The post-wipe case: a sender cannot decrypt its own ciphertext, so an
    // own row's plaintext lived only in the local cache. A fan-out row carries
    // no ciphertext for its own origin device (amendment (ix)), so this row
    // does NOT satisfy displayAsEncryptedPlaceholder — keying the relabel on
    // that predicate alone would miss exactly this row.
    await tester.pumpWidget(
      _wrap(_msg(content: '[encrypted]'), decrypting: false, isMine: true),
    );

    expect(_body("can't be read on this device"), findsOneWidget);
    expect(_body('[encrypted]'), findsNothing);
  });

  testWidgets('an own row mid-pass is not declared lost', (tester) async {
    // The lost-ack reconcile fills own rows during the pass; calling one
    // unreadable while that is still running would flash a false verdict.
    await tester.pumpWidget(
      _wrap(_msg(content: '[encrypted]'), decrypting: true, isMine: true),
    );

    expect(_body("can't be read on this device"), findsNothing);
  });

  testWidgets('a peer row awaiting the pass is not declared lost',
      (tester) async {
    // Guards the regression the narrow rule exists to prevent: the frame
    // before `decryptInProgress` goes true must not claim the row is lost, or
    // every cold chat entry flashes a false verdict before showing text.
    await tester.pumpWidget(
      _wrap(
        _msg(content: '[encrypted]', encryptedContent: '2:abc'),
        decrypting: false,
      ),
    );

    expect(_body("can't be read on this device"), findsNothing);
  });
}
