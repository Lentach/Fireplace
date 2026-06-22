import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/message_metadata_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

MessageModel _msg({DateTime? editedAt}) => MessageModel(
      id: 1,
      content: 'hi',
      senderId: 1,
      senderUsername: 'me',
      conversationId: 1,
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      deliveryStatus: MessageDeliveryStatus.sent,
      editedAt: editedAt,
    );

Future<void> _pump(WidgetTester tester, MessageModel message) {
  return tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => MessagingProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: MessageMetadataRow(
            message: message,
            isMine: true,
            timeColor: Colors.grey,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows "edited" when editedAt is set', (tester) async {
    await _pump(tester, _msg(editedAt: DateTime.now()));
    await tester.pump();
    expect(find.text('edited'), findsOneWidget);
  });

  testWidgets('hides "edited" when editedAt is null', (tester) async {
    await _pump(tester, _msg());
    await tester.pump();
    expect(find.text('edited'), findsNothing);
  });
}
