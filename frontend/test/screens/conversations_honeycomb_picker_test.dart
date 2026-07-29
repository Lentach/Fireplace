import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/conversations_screen.dart';
import 'package:fireplace/screens/invitations_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/chat_honeycomb_picker.dart';
import 'package:fireplace/widgets/hex_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(this._user);

  final UserModel _user;

  @override
  UserModel? get currentUser => _user;

  @override
  String? get token => 'test-token';

  @override
  Future<void> ensureSessionReady() async {}
}

class _FakeConnectionProvider extends ConnectionProvider {
  @override
  Future<void> connect(int userId, String token, String baseUrl) async {}
}

Widget _host({
  required FriendsProvider friends,
  required ConversationsProvider conversations,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) =>
            _FakeAuthProvider(UserModel(id: 1, username: 'Marta', tag: '0007')),
      ),
      ChangeNotifierProvider<ConnectionProvider>(
        create: (_) => _FakeConnectionProvider(),
      ),
      ChangeNotifierProvider.value(value: friends),
      ChangeNotifierProvider.value(value: conversations),
      ChangeNotifierProvider<SettingsProvider>.value(
        value: SettingsProvider(initialThemePreference: 'dark'),
      ),
      ChangeNotifierProvider(create: (_) => EncryptionProvider()),
      ChangeNotifierProvider(create: (_) => MessagingProvider()),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          disableAnimations: true,
        ),
        child: const ConversationsScreen(),
      ),
    ),
  );
}

FriendsProvider _friends(List<UserModel> users) =>
    FriendsProvider()..onFriendsList([
      for (final user in users)
        {
          'id': user.id,
          'username': user.username,
          'tag': user.tag,
          'profilePictureUrl': user.profilePictureUrl,
        },
    ]);

FriendsProvider _friendsWithInvite(List<UserModel> users) =>
    _friends(users)..onFriendRequestsList([
      {
        'id': 11,
        'sender': {'id': 5, 'username': 'Nina', 'tag': '0005'},
        'receiver': {'id': 1, 'username': 'Marta', 'tag': '0007'},
        'status': 'pending',
        'createdAt': '2026-07-29T12:00:00.000Z',
      },
    ]);

ConversationsProvider _conversationsWithAda() {
  return ConversationsProvider()
    ..setCurrentUserId(1)
    ..onConversationsList([
      {
        'id': 42,
        'userOne': {'id': 1, 'username': 'Marta', 'tag': '0007'},
        'userTwo': {'id': 2, 'username': 'Ada', 'tag': '0002'},
        'createdAt': '2026-07-27T12:00:00.000Z',
      },
    ]);
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversations-new-chat-button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the Chats plus opens a honeycomb and opens its conversation', (
    tester,
  ) async {
    final conversations = _conversationsWithAda();
    await tester.pumpWidget(
      _host(
        friends: _friends([
          UserModel(id: 2, username: 'Ada', tag: '0002'),
          UserModel(id: 3, username: 'Borys', tag: '0003'),
        ]),
        conversations: conversations,
      ),
    );
    await tester.pump();

    await _openPicker(tester);

    expect(find.byKey(const Key('chat-honeycomb-picker')), findsOneWidget);
    expect(find.byType(ChatHoneycombPicker), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatHoneycombPicker),
        matching: find.byType(HexAvatar),
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.byKey(const Key('chat-picker-friend-2')));
    await tester.pump();

    expect(conversations.activeConversationId, 42);
  });

  testWidgets('the picker gives an empty friend list a useful state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(friends: _friends([]), conversations: ConversationsProvider()),
    );
    await tester.pump();

    await _openPicker(tester);

    expect(find.byKey(const Key('chat-honeycomb-empty-state')), findsOneWidget);
    expect(find.text('No friends yet'), findsOneWidget);
    expect(find.text('Add a friend to start a chat.'), findsOneWidget);
  });

  testWidgets('reduce motion renders the picker entrance immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataDarkGray,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: const ChatHoneycombPicker(friends: []),
        ),
      ),
    );

    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(ChatHoneycombPicker),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      1,
    );
  });

  testWidgets('reduce motion turned on mid-entrance snaps the picker to its '
      'end state', (tester) async {
    Widget host({required bool reduceMotion}) => MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: reduceMotion,
        ),
        child: const ChatHoneycombPicker(friends: []),
      ),
    );

    await tester.pumpWidget(host(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 60));

    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(ChatHoneycombPicker),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    expect(opacity(), lessThan(1), reason: 'entrance should be mid-flight');

    // The reduce-motion check must run on EVERY dependency change, not be
    // latched by the one-shot entrance guard: a user switching the setting on
    // mid-animation has to see it honored (playbook §9).
    await tester.pumpWidget(host(reduceMotion: true));
    await tester.pump();

    expect(opacity(), 1);
  });

  _pickerNameTests();
}

// A comb of bare avatars is unreadable the moment someone has no picture:
// every such terminal is one initial. The name is the identifier.
void _pickerNameTests() {
  testWidgets('every picker terminal is captioned with its username', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        friends: _friends([
          UserModel(id: 2, username: 'Ada', tag: '0002'),
          UserModel(id: 3, username: 'Borys', tag: '0003'),
        ]),
        conversations: _conversationsWithAda(),
      ),
    );
    await tester.pump();
    await _openPicker(tester);

    for (final name in ['Ada', 'Borys']) {
      expect(
        find.descendant(
          of: find.byType(ChatHoneycombPicker),
          matching: find.text(name),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('an inbound invitation is a comb terminal that opens the queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        friends: _friendsWithInvite([
          UserModel(id: 2, username: 'Ada', tag: '0002'),
        ]),
        conversations: _conversationsWithAda(),
      ),
    );
    await tester.pump();
    await _openPicker(tester);

    // The "+" badge counts inbound invitations; the sheet behind it has to be
    // able to answer one, and has to name who is waiting.
    expect(
      find.descendant(
        of: find.byType(ChatHoneycombPicker),
        matching: find.text('Nina'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ChatHoneycombPicker),
        matching: find.text('Pending'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('chat-picker-invitations-hint')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('chat-picker-invite-5')));
    // Not pumpAndSettle: the invitation queue paints skeletonizer shimmer,
    // which never reaches a settled frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InvitationsScreen), findsOneWidget);
  });

  testWidgets('no invitations leaves the comb free of the invitation hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        friends: _friends([UserModel(id: 2, username: 'Ada', tag: '0002')]),
        conversations: _conversationsWithAda(),
      ),
    );
    await tester.pump();
    await _openPicker(tester);

    expect(find.byKey(const Key('chat-picker-invitations-hint')), findsNothing);
    expect(find.byKey(const Key('chat-picker-invite-5')), findsNothing);
  });
}
