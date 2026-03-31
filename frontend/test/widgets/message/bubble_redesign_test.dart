import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/chat_message_bubble.dart';
import 'package:fireplace/widgets/message/gif_message_content.dart';
import 'package:fireplace/widgets/message/image_message_content.dart';
import 'package:fireplace/widgets/message/text_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

MessageModel _gifMessage() => MessageModel(
      id: 1,
      content: '',
      senderId: 1,
      senderUsername: 'a',
      conversationId: 1,
      deliveryStatus: MessageDeliveryStatus.read,
      messageType: MessageType.gif,
      createdAt: DateTime(2026, 1, 1, 14, 30),
      mediaUrl: 'https://example.com/test.gif',
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ],
          child: child,
        ),
      ),
    );

Widget _wrapBubble(Widget child) => MaterialApp(
      theme: RpgTheme.themeDataBlue,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ChangeNotifierProvider<MessagingProvider>(
                create: (_) => MessagingProvider()),
          ],
          child: child,
        ),
      ),
    );

void main() {
  group('GifMessageContent', () {
    testWidgets('renders SizedBox with height 220', (tester) async {
      await tester.pumpWidget(_wrap(GifMessageContent(message: _gifMessage())));
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      expect(
        sizedBoxes.any((b) => b.height == 220.0),
        isTrue,
        reason: 'Loading placeholder must use height 220',
      );
    });

    testWidgets('does not render a ConstrainedBox with maxWidth 200', (tester) async {
      await tester.pumpWidget(_wrap(GifMessageContent(message: _gifMessage())));
      final boxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(
        boxes.any((b) => b.constraints.maxWidth == 200.0),
        isFalse,
        reason: 'GIF must not be capped at 200px',
      );
    });
  });

  group('ImageMessageContent', () {
    testWidgets('loading placeholder uses height 220', (tester) async {
      final msg = MessageModel(
        id: 2,
        content: '',
        senderId: 1,
        senderUsername: 'a',
        conversationId: 1,
        deliveryStatus: MessageDeliveryStatus.read,
        messageType: MessageType.image,
        createdAt: DateTime(2026, 1, 1, 14, 30),
        mediaUrl: 'https://example.com/test.jpg',
      );
      await tester.pumpWidget(_wrap(ImageMessageContent(message: msg)));
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      expect(
        sizedBoxes.any((b) => b.height == 220.0),
        isTrue,
        reason: 'Loading placeholder must use height 220',
      );
    });

    testWidgets('does not render ConstrainedBox with maxWidth 200', (tester) async {
      final msg = MessageModel(
        id: 2,
        content: '',
        senderId: 1,
        senderUsername: 'a',
        conversationId: 1,
        deliveryStatus: MessageDeliveryStatus.read,
        messageType: MessageType.image,
        createdAt: DateTime(2026, 1, 1, 14, 30),
        mediaUrl: 'https://example.com/test.jpg',
      );
      await tester.pumpWidget(_wrap(ImageMessageContent(message: msg)));
      final boxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(
        boxes.any((b) => b.constraints.maxWidth == 200.0),
        isFalse,
      );
    });
  });

  group('TextMessageContent overlay', () {
    testWidgets('renders Stack with Positioned when timeOverlay provided', (tester) async {
      final msg = MessageModel(
        id: 3,
        content: 'Hej co słychać dzisiaj u ciebie?',
        senderId: 1,
        senderUsername: 'a',
        conversationId: 1,
        deliveryStatus: MessageDeliveryStatus.read,
        messageType: MessageType.text,
        createdAt: DateTime(2026, 1, 1, 14, 30),
      );
      const overlay = SizedBox(key: Key('time-overlay'), width: 60, height: 16);
      await tester.pumpWidget(_wrap(
        TextMessageContent(
          message: msg,
          isMine: true,
          textColor: Colors.white,
          isDark: true,
          maxWidth: 250,
          timeOverlay: overlay,
        ),
      ));
      expect(find.byKey(kTextMessageTimeOverlayStackKey), findsOneWidget);
      expect(find.byKey(const Key('time-overlay')), findsOneWidget);
      final positioned = tester.widgetList<Positioned>(find.byType(Positioned));
      expect(positioned.any((p) => p.bottom == 0 && p.right == 0), isTrue);
    });

    testWidgets('renders plain Column when timeOverlay is null', (tester) async {
      final msg = MessageModel(
        id: 4,
        content: 'Hello',
        senderId: 1,
        senderUsername: 'a',
        conversationId: 1,
        deliveryStatus: MessageDeliveryStatus.read,
        messageType: MessageType.text,
        createdAt: DateTime(2026, 1, 1, 14, 30),
      );
      await tester.pumpWidget(_wrap(
        TextMessageContent(
          message: msg,
          isMine: true,
          textColor: Colors.white,
          isDark: true,
          maxWidth: 250,
        ),
      ));
      expect(find.byKey(kTextMessageTimeOverlayStackKey), findsNothing);
    });
  });

  group('ChatMessageBubble routing', () {
    testWidgets('GIF bubble: Container has zero padding', (tester) async {
      final msg = MessageModel(
        id: 5,
        content: '',
        senderId: 1,
        senderUsername: 'a',
        conversationId: 1,
        deliveryStatus: MessageDeliveryStatus.read,
        messageType: MessageType.gif,
        createdAt: DateTime(2026, 1, 1, 14, 30),
        mediaUrl: 'https://example.com/test.gif',
      );
      await tester.pumpWidget(_wrapBubble(
        ChatMessageBubble(message: msg, isMine: true),
      ));
      final containers = tester.widgetList<Container>(find.byType(Container));
      expect(
        containers.any((c) => c.padding == EdgeInsets.zero),
        isTrue,
        reason: 'GIF bubble must have zero padding',
      );
    });

    testWidgets('text bubble (>25 chars, no link preview): renders overlay stack',
        (tester) async {
      final msg = MessageModel(
        id: 6,
        content: 'Hej, co słychać u Ciebie dzisiaj wieczorem?',
        senderId: 1,
        senderUsername: 'a',
        conversationId: 1,
        deliveryStatus: MessageDeliveryStatus.read,
        messageType: MessageType.text,
        createdAt: DateTime(2026, 1, 1, 14, 30),
      );
      await tester.pumpWidget(_wrapBubble(
        ChatMessageBubble(message: msg, isMine: true),
      ));
      expect(find.byKey(kTextMessageTimeOverlayStackKey), findsOneWidget);
    });
  });
}
