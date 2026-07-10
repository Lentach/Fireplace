// Throwaway visual harness for the Liquid Glass chrome (NOT shipped; run:
// flutter run -d web-server -t tool/glass_preview.dart).
// Hosts the real MainTabScreenHeader + GlassBottomNav + ConversationTile over
// fake data; ?theme=blue|dark|light|teal picks the theme.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fireplace/providers/settings_provider.dart';

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

class GlassPreviewApp extends StatelessWidget {
  const GlassPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeName = Uri.base.queryParameters['theme'] ?? 'dark';
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(themeName),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _ChatListPreview(),
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
