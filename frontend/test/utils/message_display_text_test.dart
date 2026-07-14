import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/utils/message_display_text.dart';

MessageModel _msg(String content) => MessageModel(
      id: 1,
      content: content,
      senderId: 2,
      senderUsername: 'bob',
      conversationId: 10,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  Future<String> resolve(WidgetTester tester, MessageModel m) async {
    late String out;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            out = messageDisplayContent(ctx, m);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return out;
  }

  testWidgets('maps [Decryption failed] to the localized string', (t) async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(await resolve(t, _msg('[Decryption failed]')), en.decryptionFailed);
  });

  testWidgets('maps [Encryption not initialized] to the localized string',
      (t) async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      await resolve(t, _msg('[Encryption not initialized]')),
      en.encryptionNotInitialized,
    );
  });

  testWidgets('returns plaintext content verbatim when present', (t) async {
    expect(await resolve(t, _msg('hello world')), 'hello world');
  });

  testWidgets('empty content falls back to unsupported-type string', (t) async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(await resolve(t, _msg('')), en.unsupportedMessageType);
  });
}
