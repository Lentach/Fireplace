// Throwaway visual harness for the invitation surfaces (not part of flutter test).
// Run: flutter run -d web-server -t test/preview/invitations_preview.dart
// Query parameters:
//   ?theme=cosmic|blue|dark|light|teal
//   &view=inbox|picker|picker-empty|header
//   &friends=N&inviters=N&incoming=N&sent=N&accepted=1
//   &textScale=1.6&reduceMotion=1
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/screens/invitations_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/widgets/chat_honeycomb_picker.dart';
import 'package:fireplace/widgets/glass/glass_top_bar.dart';
import 'package:fireplace/widgets/hex_avatar.dart';
import 'package:fireplace/widgets/ping_effect_overlay.dart';

void main() => runApp(const InvitationsPreviewApp());

ThemeData _theme(String name) => switch (name) {
  'cosmic' => RpgTheme.themeDataCosmic,
  'blue' => RpgTheme.themeDataBlue,
  'light' => RpgTheme.themeDataLight,
  'teal' => RpgTheme.themeDataTealStone,
  _ => RpgTheme.themeDataDarkGray,
};

const _names = [
  'Ada',
  'Borys',
  'Celina',
  'Dominik',
  'Ewa',
  'Franek',
  'Gosia',
  'Hubert',
];

Map<String, Object?> _user(int id, String name) => {
  'id': id,
  'username': name,
  'tag': id.toString().padLeft(4, '0'),
  'profilePictureUrl': null,
};

class InvitationsPreviewApp extends StatelessWidget {
  const InvitationsPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final query = Uri.base.queryParameters;
    final theme = query['theme'] ?? 'cosmic';
    final view = query['view'] ?? 'inbox';
    final textScale = double.tryParse(query['textScale'] ?? '') ?? 1;
    final reduceMotion = query['reduceMotion'] == '1';
    final friendCount = int.tryParse(query['friends'] ?? '') ?? 5;
    final inviterCount = int.tryParse(query['inviters'] ?? '') ?? 1;
    final incoming = int.tryParse(query['incoming'] ?? '') ?? 2;
    final sent = int.tryParse(query['sent'] ?? '') ?? 1;
    final accepted = query['accepted'] == '1';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(theme),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: switch (view) {
        'picker' => _PickerHost(
          friends: [
            for (var i = 0; i < friendCount; i++)
              UserModel(
                id: 2 + i,
                username: _names[i % _names.length],
                tag: '000${2 + i}',
              ),
          ],
          inviters: [
            for (var i = 0; i < inviterCount; i++)
              UserModel(id: 50 + i, username: 'Nina$i', tag: '005$i'),
          ],
        ),
        'picker-empty' => const _PickerHost(friends: [], inviters: []),
        'header' => const _ChatHeaderPreview(),
        'ping' => const _PingPreview(),
        _ => _seededInbox(incoming: incoming, sent: sent, accepted: accepted),
      },
    );
  }

  Widget _seededInbox({
    required int incoming,
    required int sent,
    required bool accepted,
  }) {
    final friends = FriendsProvider()
      ..setCurrentUserId(1)
      ..onFriendRequestsList([
        for (var i = 0; i < incoming; i++)
          {
            'id': 10 + i,
            'sender': _user(2 + i, _names[i % _names.length]),
            'receiver': _user(1, 'Marta'),
            'status': 'pending',
            'createdAt': '2026-07-29T12:00:00.000Z',
          },
      ])
      ..onSentRequestsList([
        for (var i = 0; i < sent; i++)
          {
            'id': 30 + i,
            'sender': _user(1, 'Marta'),
            'receiver': _user(20 + i, _names[(i + 3) % _names.length]),
            'status': 'pending',
            'createdAt': '2026-07-29T12:00:00.000Z',
          },
      ]);
    if (accepted) {
      friends.onFriendRequestAccepted({
        'id': 40,
        'sender': _user(60, 'Iwo'),
        'receiver': _user(1, 'Marta'),
        'status': 'accepted',
        'createdAt': '2026-07-29T12:00:00.000Z',
        'conversationId': 44,
        'chatReady': true,
      });
    }
    // Fake server echo: there is no socket here, and without one an Accept
    // would lock the row into its in-flight spinner forever (the provider
    // only emits; state advances when the SERVER answers). Answer accept /
    // decline / chat-setup after a realistic beat so the accept flow — and
    // the forge animation it triggers — is reviewable in the preview.
    final requestsById = {
      for (var i = 0; i < incoming; i++)
        10 + i: {
          'id': 10 + i,
          'sender': _user(2 + i, _names[i % _names.length]),
          'receiver': _user(1, 'Marta'),
          'status': 'accepted',
          'createdAt': '2026-07-29T12:00:00.000Z',
          'conversationId': 100 + i,
          'chatReady': true,
        },
    };
    friends.setEmitCallback((event, data) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        // NOT `as Map<String, dynamic>`: the provider emits inferred-type
        // literals (e.g. Map<String, int>), and a failed cast inside this
        // delayed future is swallowed silently — the row spins forever.
        final payload = data as Map;
        switch (event) {
          case 'acceptFriendRequest':
            final request = requestsById[payload['requestId']];
            if (request != null) friends.onFriendRequestAccepted(request);
          case 'rejectFriendRequest':
            final request = requestsById[payload['requestId']];
            if (request != null) friends.onFriendRequestRejected(request);
          case 'ensureInvitationChat':
            friends.onInvitationChatReady({
              'peerUserId': payload['peerUserId'],
              'correlationId': payload['correlationId'],
              'conversationId': 200,
              'chatReady': true,
            });
        }
      });
    });
    return ChangeNotifierProvider.value(
      value: friends,
      child: const InvitationsScreen(),
    );
  }
}

/// Opens the REAL glass sheet with the picker on first frame, so the
/// screenshot shows production chrome rather than a lookalike.
class _PickerHost extends StatefulWidget {
  const _PickerHost({required this.friends, required this.inviters});

  final List<UserModel> friends;
  final List<UserModel> inviters;

  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showChatHoneycombPicker(
        context,
        friends: widget.friends,
        inviters: widget.inviters,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}

/// The chat header's hex avatar slot, without the full messaging stack.
class _ChatHeaderPreview extends StatelessWidget {
  const _ChatHeaderPreview();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {},
        ),
        title: Text(
          'Ada',
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        avatar: HexAvatar(
          size: GlassTopBar.capsuleHeight,
          displayName: 'Ada',
          imageUrl: null,
          surface: FireplaceColors.of(context).convItemBg,
          borderColor: FireplaceColors.of(context).convItemBorder,
          initialsStyle: RpgTheme.bodyFont(
            fontSize: GlassTopBar.capsuleHeight * 0.34,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: Container(color: FireplaceColors.of(context).messagesAreaBg),
    );
  }
}

/// Remounts the ping overlay in a loop so any screenshot catches the hex
/// lattice mid-flight.
class _PingPreview extends StatefulWidget {
  const _PingPreview();

  @override
  State<_PingPreview> createState() => _PingPreviewState();
}

class _PingPreviewState extends State<_PingPreview> {
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: FireplaceColors.of(context).messagesAreaBg),
          PingEffectOverlay(
            key: ValueKey(_generation),
            onComplete: () {
              if (mounted) setState(() => _generation++);
            },
          ),
        ],
      ),
    );
  }
}
