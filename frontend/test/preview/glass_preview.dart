// Throwaway visual harness for the Liquid Glass chrome (dev-only, NOT part
// of the test suite; run: flutter run -d web-server -t test/preview/glass_preview.dart).
// Hosts the real MainTabScreenHeader + GlassBottomNav + ConversationTile over
// fake data; ?theme=blue|dark|light|teal picks the theme.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/chat_detail_screen.dart';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/conversation_tile.dart';
import 'package:fireplace/widgets/glass/glass_bottom_nav.dart';
import 'package:fireplace/widgets/main_tab_screen_header.dart';

void main() => runApp(const GlassPreviewApp());

ThemeData _theme(String name) => switch (name) {
  'blue' => RpgTheme.themeDataBlue,
  'light' => RpgTheme.themeDataLight,
  'teal' => RpgTheme.themeDataTealStone,
  _ => RpgTheme.themeDataDarkGray,
};

const _jwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoiYWxpY2UiLCJ0YWciOiIwMDAxIiwiZXhwIjo5OTk5OTk5OTl9.abc';

class GlassPreviewApp extends StatelessWidget {
  const GlassPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeName = Uri.base.queryParameters['theme'] ?? 'dark';
    final screen = Uri.base.queryParameters['screen'] ?? 'list';

    final conversations = ConversationsProvider()..setCurrentUserId(1);
    conversations.onConversationsList([
      {
        'id': 10,
        'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
        'userTwo': {'id': 2, 'username': 'Zosia', 'tag': '0002'},
        'createdAt': '2026-01-01T00:00:00.000Z',
        'unreadCount': 0,
        'lastMessage': null,
      },
    ]);
    conversations.openConversation(10, notify: false);

    final messaging = MessagingProvider();
    messaging.setIncomingMessageSoundEnabledForTest(false);
    messaging.setConversationsProvider(conversations);
    messaging.setCurrentUserId(1);
    messaging.setToken('tok');
    messaging.setEmitCallback((event, data) {});
    messaging.onConnect(false);
    messaging.setActiveConversationIdForTest(10);
    final texts = [
      'We got the whole cabin to ourselves this weekend. Bring the good blankets and I’ll handle firewood + food.',
      'Deal. I’m taking the early train, should be there by noon. Want me to grab those cinnamon buns from the bakery near the station?',
      'YES. Two bags. Last time they were gone before the fire even got going',
      'Noted — two bags, zero self-control.',
      'That campfire photo from Mazury is unreal, send the full-res one when you’re home?',
      'Uploading tonight. It’s 40MB of pure smoke and bad focus.',
    ];
    messaging.seedCacheForTest(10, [
      for (var i = 0; i < texts.length; i++)
        MessageModel.fromJson({
          'id': 1000 + i,
          'content': texts[i],
          'senderId': i.isOdd ? 1 : 2,
          'senderUsername': i.isOdd ? 'alice' : 'Zosia',
          'conversationId': 10,
          'deliveryStatus': 'READ',
          'messageType': 'TEXT',
          'createdAt': DateTime.utc(2026, 7, 10, 10, 42 + i).toIso8601String(),
        }),
    ]);
    messaging.loadCachedMessages(10);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ConversationsProvider>.value(
          value: conversations,
        ),
        ChangeNotifierProvider<MessagingProvider>.value(value: messaging),
        ChangeNotifierProvider(
          create: (_) => AuthProvider()..setAccessTokenForTest(_jwt),
        ),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider.value(value: EncryptionProvider()),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(initialThemePreference: themeName),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(themeName),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen == 'chat'
            ? const ChatDetailScreen(conversationId: 10)
            : const _ChatListPreview(),
      ),
    );
  }
}

class _ChatListPreview extends StatefulWidget {
  const _ChatListPreview();

  @override
  State<_ChatListPreview> createState() => _ChatListPreviewState();
}

class _ChatListPreviewState extends State<_ChatListPreview> {
  int _index = 0;

  static final _names = [
    'Aunt Marta', 'Kuba', 'Zosia', 'Dev Standup', 'Michał', 'Ola',
    'Piotrek', 'Basia', 'Tomek', 'Kasia', 'Wojtek', 'Ela', // scroll fodder
  ];

  MessageModel _msg(int i) => MessageModel(
    id: i,
    conversationId: i,
    senderId: 99,
    senderUsername: _names[i % _names.length],
    content: [
      'typing…',
      'PING!',
      'That campfire photo from Mazury is unreal',
      'ok, sending the keys over signal tonight',
      'the marshmallow completely melted',
      'see you at the cabin on saturday then?',
    ][i % 6],
    messageType: MessageType.text,
    createdAt: DateTime.now().subtract(Duration(hours: i * 3)),
    deliveryStatus: MessageDeliveryStatus.read,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final media = MediaQuery.paddingOf(context);
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    media.top + MainTabScreenHeader.clearance,
                    8,
                    media.bottom + 8,
                  ),
                  itemCount: _names.length,
                  separatorBuilder: (_, i) => Divider(
                    height: 1,
                    color: Theme.of(context).dividerTheme.color,
                  ),
                  itemBuilder: (context, i) => ConversationTile(
                    conversationId: i,
                    displayName: _names[i],
                    lastMessage: _msg(i),
                    isActive: i == 1,
                    unreadCount: i == 1 ? 2 : (i == 5 ? 5 : 0),
                    onTap: () {},
                    onDelete: () {},
                    otherUser: UserModel(
                      id: i,
                      username: _names[i],
                      tag: '0000',
                    ),
                    isTyping: i == 0,
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MainTabScreenHeader(
              title: 'Chat',
              leading: const CircleAvatar(radius: 22, child: Text('J')),
              trailing: IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                onPressed: () {},
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: GlassBottomNav(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          destinations: const [
            GlassNavDestination(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Chat',
            ),
            GlassNavDestination(
              icon: Icon(Icons.people_outline),
              label: 'Contacts',
            ),
            GlassNavDestination(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
