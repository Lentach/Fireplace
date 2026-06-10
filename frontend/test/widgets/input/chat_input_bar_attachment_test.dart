import 'dart:typed_data';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/encrypted_media_upload_service.dart';
import 'package:fireplace/services/media_crypto_service.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 1x1 transparent PNG so Image.memory decodes without errors.
final kTinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakeMediaUpload extends EncryptedMediaUploadService {
  _FakeMediaUpload({this.throwOnUpload})
      : super(api: ApiService(baseUrl: 'http://test'));

  final Object? throwOnUpload;

  @override
  Future<EncryptedMediaUpload> encryptAndUpload({
    required Uint8List bytes,
    required String token,
    required String mediaType,
    int? duration,
    int? expiresIn,
    String? fileName,
    void Function(String keyBase64, String ivBase64)? onEncrypted,
  }) async {
    onEncrypted?.call('K', 'IV');
    if (throwOnUpload != null) throw throwOnUpload!;
    return EncryptedMediaUpload(
      mediaUrl: 'http://test/media/msgs/x.bin',
      keyBase64: 'K',
      ivBase64: 'IV',
      mediaDuration: duration,
    );
  }
}

class _SendReadyEncryption extends EncryptionProvider {
  @override
  bool get isE2EReady => true;

  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> ensureSession(int recipientId) async {}

  @override
  Future<String> encrypt(int recipientId, String plaintext) async => '1:abc';

  @override
  Future<Map<String, dynamic>?> getDecryptedContent(int messageId) async =>
      null;
}

Future<({GlobalKey<ChatInputBarState> key, List<String> emitted})> pumpComposer(
  WidgetTester tester, {
  Object? throwOnUpload,
}) async {
  final key = GlobalKey<ChatInputBarState>();
  final emitted = <String>[];

  final convs = ConversationsProvider();
  convs.onConversationsList([
    {
      'id': 10,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': '2026-01-01T00:00:00.000Z',
      'unreadCount': 0,
      'lastMessage': null,
    },
  ]);
  convs.openConversation(10);

  final messaging = MessagingProvider();
  messaging.setConversationsProvider(convs);
  messaging.setCurrentUserId(1);
  messaging.setToken('tok');
  messaging.onConnect(false);
  messaging.setMediaUploadServiceForTest(
    _FakeMediaUpload(throwOnUpload: throwOnUpload),
  );
  messaging.setEncryptionProvider(_SendReadyEncryption());
  messaging.setEmitCallback((event, data) {
    if (event == 'sendMessage') {
      emitted.add((data as Map)['messageType'] as String? ?? 'TEXT');
    }
  });

  final auth = AuthProvider()..setAccessTokenForTest('tok');

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: RpgTheme.themeDataLight,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<ConversationsProvider>.value(value: convs),
            ChangeNotifierProvider<MessagingProvider>.value(value: messaging),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(initialThemePreference: 'light'),
            ),
          ],
          child: ChatInputBar(key: key),
        ),
      ),
    ),
  );
  return (key: key, emitted: emitted);
}

void main() {
  testWidgets('staged image shows chip; remove clears it', (tester) async {
    final h = await pumpComposer(tester);

    h.key.currentState!.attachmentControllerForTest.stage(
      bytes: kTinyPng,
      mimeType: 'image/png',
      filename: 'pasted.png',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsOneWidget);
    expect(find.text('pasted.png'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer_attachment_remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsNothing);
  });

  testWidgets('send affordance visible with staged image and empty text',
      (tester) async {
    final h = await pumpComposer(tester);
    final layer = find.byKey(const ValueKey('composer_text_send_layer'));

    AnimatedOpacity opacityOf() => tester.widget<AnimatedOpacity>(
        find.descendant(of: layer, matching: find.byType(AnimatedOpacity)));

    expect(opacityOf().opacity, 0.0); // empty composer: mic showing

    h.key.currentState!.attachmentControllerForTest.stage(
      bytes: kTinyPng,
      mimeType: 'image/png',
      filename: 'pasted.png',
    );
    await tester.pumpAndSettle();

    expect(opacityOf().opacity, 1.0);
  });

  testWidgets('send: image emits before caption; composer fully cleared',
      (tester) async {
    final h = await pumpComposer(tester);

    h.key.currentState!.attachmentControllerForTest.stage(
      bytes: kTinyPng,
      mimeType: 'image/png',
      filename: 'pasted.png',
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my caption');

    h.key.currentState!.sendForTest();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    expect(h.emitted, ['IMAGE', 'TEXT']); // ordering contract end-to-end
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsNothing);
  });

  testWidgets('image failure: caption restored, no TEXT emit, can retry send',
      (tester) async {
    final h = await pumpComposer(tester, throwOnUpload: Exception('boom'));

    h.key.currentState!.attachmentControllerForTest.stage(
      bytes: kTinyPng,
      mimeType: 'image/png',
      filename: 'pasted.png',
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my caption');

    h.key.currentState!.sendForTest();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    expect(h.emitted, isEmpty); // upload threw pre-emit; caption NOT auto-sent
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'my caption', // ordering contract rule 3: user keeps their words
    );
    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsNothing); // failed optimistic bubble owns retry, not the chip

    // Guard reset: a plain text send still works afterwards.
    h.key.currentState!.sendForTest();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.emitted, ['TEXT']);
  });

  testWidgets('pasted text inserts at the cursor, replacing the selection',
      (tester) async {
    final h = await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'hello world');
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    controller.selection =
        const TextSelection(baseOffset: 6, extentOffset: 11);

    h.key.currentState!.insertPastedTextForTest('there');
    await tester.pump();

    expect(controller.text, 'hello there');
    expect(controller.selection,
        const TextSelection.collapsed(offset: 11));
  });

  testWidgets('oversize pasted image: snackbar, nothing staged',
      (tester) async {
    final h = await pumpComposer(tester);

    h.key.currentState!.handlePastedImageForTest(
      Uint8List(MediaCryptoService.maxBytes + 1),
      'image/png',
      'huge.png',
    );
    await tester.pump();

    expect(find.text('Image is too large (max 20 MB)'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsNothing);
    await tester.pump(const Duration(seconds: 3)); // flush snackbar timer
  });

  testWidgets('unsupported pasted image type: snackbar, nothing staged',
      (tester) async {
    final h = await pumpComposer(tester);

    h.key.currentState!.handlePastedImageForTest(
      kTinyPng,
      'image/tiff', // image/* but outside kStageableImageMimeTypes
      'scan.tiff',
    );
    await tester.pump();

    expect(find.text("This image type can't be pasted"), findsOneWidget);
    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('valid pasted image stages the chip via the paste handler',
      (tester) async {
    final h = await pumpComposer(tester);

    h.key.currentState!.handlePastedImageForTest(
      kTinyPng,
      'image/png',
      'pasted.png',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('composer_attachment_thumb')),
        findsOneWidget);
  });
}
