import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/message_context_menu_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg({required int id, required int senderId}) => MessageModel(
      id: id,
      content: 'hello',
      senderId: senderId,
      senderUsername: 'alice',
      conversationId: 1,
      createdAt: DateTime(2026, 5, 23),
      deliveryStatus: MessageDeliveryStatus.sent,
      messageType: MessageType.text,
    );

void main() {
  testWidgets('long-press entry shows four action labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: GestureDetector(
                onLongPress: () {
                  final box = ctx.findRenderObject() as RenderBox;
                  openMessageContextMenu(
                    context: ctx,
                    message: _msg(id: 10, senderId: 1),
                    bubbleRenderBox: box,
                    isMine: true,
                    currentUserId: 1,
                    onReply: () {},
                    onPin: () {},
                    onDelete: () {},
                    onReaction: (emoji, alreadyReacted) {},
                  );
                },
                child: const Text('bubble'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('bubble'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
