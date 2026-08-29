// The peer-identity alarm row must be reachable in an EMPTY conversation.
//
// It was not. `_buildMessagesArea` gated the whole timeline on
// `messages.isEmpty` and rendered the row ONLY inside the `ListView.builder`
// of the non-empty branch, so `identityRowOffset` was computed and then
// discarded. The single machine-in-the-middle warning this product has was
// therefore suppressed in exactly the conversations most likely to be empty:
// cleared history, fully expired history, a conversation deleted and refriended,
// or a peer who reset before the first message — and the server
// `peerIdentityChanged` event (connection_provider.dart -> 
// recordPeerIdentityChangedFromServer) raises the warning with NO local message
// required, so the empty chat is not a corner case.
//
// SCOPE OF THIS FILE: the SCREEN's render decision only. A fake provider is
// used deliberately here, because the production chain that SETS this state
// (store -> service callback -> provider notifyListeners) is proven separately
// against real objects in
// `test/providers/encryption_provider_identity_alarm_test.dart`. Faking it in
// both places is what left this hole unguarded.

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/chat_detail_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/peer_identity_changed_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _currentUserJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoiYWxpY2UiLCJ0YWciOiIwMDAxIiwiZXhwIjo5OTk5OTk5OTl9.abc';

/// The peer of conversation 10. `otherUser` resolves to this id, which is what
/// `peersWithChangedIdentity` is checked against.
const _peerId = 2;

class _AlarmedEncryption extends EncryptionProvider {
  _AlarmedEncryption({this.changedPeers = const <int>{}});

  final Set<int> changedPeers;

  @override
  Set<int> get peersWithChangedIdentity => changedPeers;

  @override
  Future<String?> getPeerIdentityFingerprint(int peerId) async => 'AAAA BBBB';

  @override
  Future<String?> getIdentityFingerprint() async => 'CCCC DDDD';
}

Map<String, dynamic> _conversationJson() => {
  'id': 10,
  'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
  'userTwo': {'id': _peerId, 'username': 'bob', 'tag': '0002'},
  'createdAt': '2026-01-01T00:00:00.000Z',
  'unreadCount': 0,
  'lastMessage': null,
};

Map<String, dynamic> _messageJson(int id) => {
  'id': id,
  'content': 'note $id',
  'senderId': 1,
  'senderUsername': 'alice',
  'conversationId': 10,
  'deliveryStatus': 'DELIVERED',
  'messageType': 'TEXT',
  'createdAt': DateTime.utc(2026, 1, 1, 12, id % 60).toIso8601String(),
};

Future<void> _pumpChat(
  WidgetTester tester, {
  required bool alarmed,
  required bool withMessages,
}) async {
  SharedPreferences.setMockInitialValues({});

  final conversations = ConversationsProvider()..setCurrentUserId(1);
  conversations.onConversationsList([_conversationJson()]);
  conversations.openConversation(10, notify: false);

  final messaging = MessagingProvider();
  messaging.setIncomingMessageSoundEnabledForTest(false);
  messaging.setConversationsProvider(conversations);
  messaging.setCurrentUserId(1);
  messaging.setToken('tok');
  messaging.setEmitCallback((event, data) {});
  messaging.onConnect(false);
  messaging.setActiveConversationIdForTest(10);
  messaging.seedCacheForTest(10, [
    if (withMessages)
      for (var i = 0; i < 3; i++) MessageModel.fromJson(_messageJson(1000 + i)),
  ]);
  messaging.loadCachedMessages(10);

  final auth = AuthProvider()..setAccessTokenForTest(_currentUserJwt);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConversationsProvider>.value(
          value: conversations,
        ),
        ChangeNotifierProvider<MessagingProvider>.value(value: messaging),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider<EncryptionProvider>.value(
          value: _AlarmedEncryption(
            changedPeers: alarmed ? const {_peerId} : const <int>{},
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(initialThemePreference: 'dark'),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: RpgTheme.themeDataDarkGray,
        home: const ChatDetailScreen(conversationId: 10),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('an EMPTY conversation still shows the identity alarm', (
    tester,
  ) async {
    await _pumpChat(tester, alarmed: true, withMessages: false);

    expect(
      find.byType(PeerIdentityChangedRow),
      findsOneWidget,
      reason:
          'a cleared or never-used chat is where a peer reset is most likely '
          'to arrive unannounced; suppressing the warning there makes it '
          'decorative',
    );
  });

  testWidgets('an empty conversation with no alarm shows no row', (
    tester,
  ) async {
    await _pumpChat(tester, alarmed: false, withMessages: false);

    expect(
      find.byType(PeerIdentityChangedRow),
      findsNothing,
      reason:
          'a standing false alarm would train people to dismiss the one '
          'surface that detects a real takeover',
    );
  });

  testWidgets('the populated-timeline path still shows the row', (
    tester,
  ) async {
    await _pumpChat(tester, alarmed: true, withMessages: true);

    expect(find.byType(PeerIdentityChangedRow), findsOneWidget);
  });

  testWidgets('a populated timeline with no alarm shows no row', (
    tester,
  ) async {
    await _pumpChat(tester, alarmed: false, withMessages: true);

    expect(find.byType(PeerIdentityChangedRow), findsNothing);
  });
}
