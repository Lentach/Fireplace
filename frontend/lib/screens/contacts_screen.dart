import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/user_model.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/contact_network_view.dart';
import '../widgets/main_tab_screen_header.dart';
import '../utils/instant_opaque_route.dart';
import 'chat_detail_screen.dart';
import 'user_card_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  /// The network map is the primary presentation; the classic list stays one
  /// tap away as the accessibility / fast-lookup fallback.
  bool _showList = false;

  void _openChatWithContact(BuildContext context, int userId) {
    final convs = context.read<ConversationsProvider>();

    // Check if conversation exists for this user
    final existingConv = convs.conversations.where((conv) {
      final otherUser = convs.getOtherUser(conv);
      return otherUser?.id == userId;
    }).firstOrNull;

    if (existingConv != null) {
      // Conversation exists, open it
      convs.openConversation(existingConv.id);

      final width = MediaQuery.of(context).size.width;
      if (width < AppConstants.layoutBreakpointDesktop) {
        Navigator.of(context).push(
          instantOpaqueRoute(
            builder: (_) => ChatDetailScreen(conversationId: existingConv.id),
          ),
        );
      }
    } else {
      // No conversation, start new one (backend will create)
      convs.startConversation(userId);
      // consumePendingOpen will handle navigation when backend responds
    }
  }

  void _openContactCard(BuildContext context, UserModel user) {
    final convs = context.read<ConversationsProvider>();
    final existingConversation = convs.conversations.where(
      (conversation) => convs.getOtherUser(conversation)?.id == user.id,
    ).firstOrNull;
    final hasConversation = existingConversation != null;

    Navigator.of(context).push(
      instantOpaqueRoute(
        builder: (cardContext) => UserCardScreen(
          data: UserCardVisualData.fromUser(
            user,
            isSelf: false,
            hasConversation: hasConversation,
            conversationId: existingConversation?.id,
            mute: UserCardMute.fromConversation(
              muted: existingConversation?.muted ?? false,
              mutedUntil: existingConversation?.mutedUntil,
            ),
          ),
          onMessage: () {
            Navigator.of(cardContext).pop();
            _openChatWithContact(context, user.id);
          },
          onMuteChanged: existingConversation == null
              ? null
              : (mute) {
                  convs.setConversationMute(
                    existingConversation.id,
                    switch (mute) {
                      UserCardMute.off => 'off',
                      UserCardMute.oneHour => '1h',
                      UserCardMute.eightHours => '8h',
                      UserCardMute.oneWeek => '1w',
                      UserCardMute.forever => 'forever',
                    },
                  );
                },
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final convs = context.watch<ConversationsProvider>();
    // When user tapped a contact and we had no conversation, we called startConversation.
    // Backend emits openConversation; consume it here and open chat (AddOrInvitations only consumes when that screen is open).
    if (convs.pendingOpenConversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final id = context.read<ConversationsProvider>().consumePendingOpen();
        if (id != null && context.mounted) {
          Navigator.of(context).push(
            instantOpaqueRoute(
              builder: (_) => ChatDetailScreen(conversationId: id),
            ),
          );
        }
      });
    }
    // Same floating-chrome treatment as the Chats tab (owner, round 4b):
    // the list runs full-bleed behind the transparent header capsule area
    // and the bottom nav; clearance is padding, not a layout slot.
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _showList
                ? _buildContactsList(context)
                : _buildNetwork(context),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasContacts = context.watch<FriendsProvider>().friends.isNotEmpty;
    return MainTabScreenHeader(
      title: l10n.contacts,
      trailing: hasContacts
          ? IconButton(
              onPressed: () => setState(() => _showList = !_showList),
              tooltip: _showList
                  ? l10n.contactNetworkShowMap
                  : l10n.contactNetworkShowList,
              icon: Icon(
                _showList ? Icons.hub_outlined : Icons.format_list_bulleted,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            )
          : null,
    );
  }

  Widget _buildNetwork(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final friendsProvider = context.watch<FriendsProvider>();
    final friends = List<UserModel>.from(friendsProvider.friends)
      ..sort(_compareByDisplayName);
    final convs = context.watch<ConversationsProvider>();
    final conversationContactIds = <int>{};
    for (final conversation in convs.conversations) {
      final other = convs.getOtherUser(conversation);
      if (other != null) conversationContactIds.add(other.id);
    }
    final currentUser = context.watch<AuthProvider>().currentUser;
    final media = MediaQuery.paddingOf(context);

    return ContactNetworkView(
      contacts: friends,
      localNodeLabel: currentUser?.username ?? '',
      localNodeCaption: l10n.contactNetworkLocalNode,
      emptyTitle: l10n.noContactsYet,
      emptyMessage: l10n.addFriendsToStart,
      onContactTap: (user) => _openContactCard(context, user),
      networkSemanticLabel: l10n.contactNetworkSemantic(friends.length),
      localNodeSemanticLabel: l10n.contactNetworkYouLocalNode,
      safeInsets: EdgeInsets.fromLTRB(
        12,
        media.top + MainTabScreenHeader.clearance,
        12,
        media.bottom + 8,
      ),
      storageUserId: currentUser?.id,
      resetLayoutLabel: l10n.contactNetworkReset,
      dragHint: l10n.contactNetworkDragHint,
      conversationContactIds: conversationContactIds,
      mapCaption: l10n.contactNetworkNodes(
        friends.length.toString().padLeft(2, '0'),
      ),
    );
  }

  /// Natural sort: same prefix → smaller number first (ziomek3, ziomek6, ziomek50).
  static int _compareByDisplayName(UserModel a, UserModel b) {
    final aMatch = RegExp(r'^(.+?)(\d+)$').firstMatch(a.username);
    final bMatch = RegExp(r'^(.+?)(\d+)$').firstMatch(b.username);
    final aPrefix = (aMatch?.group(1) ?? a.username).toLowerCase();
    final bPrefix = (bMatch?.group(1) ?? b.username).toLowerCase();
    final aNum = aMatch != null ? int.tryParse(aMatch.group(2)!) ?? 0 : 0;
    final bNum = bMatch != null ? int.tryParse(bMatch.group(2)!) ?? 0 : 0;

    final prefixCmp = aPrefix.compareTo(bPrefix);
    if (prefixCmp != 0) return prefixCmp;
    return aNum.compareTo(bNum);
  }

  Widget _buildContactsList(BuildContext context) {
    final friendsProvider = context.watch<FriendsProvider>();
    final friends = List<UserModel>.from(friendsProvider.friends)
      ..sort(_compareByDisplayName);
    final isDark = RpgTheme.isDark(context);
    final mutedColor = FireplaceColors.of(context).mutedText;

    final media = MediaQuery.paddingOf(context);
    final bottomClearance = media.bottom;
    final topClearance = media.top + MainTabScreenHeader.clearance;

    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            32,
            32 + topClearance,
            32,
            32 + bottomClearance,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: mutedColor),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).noContactsYet,
                style: RpgTheme.bodyFont(fontSize: 16, color: mutedColor),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).addFriendsToStart,
                style: RpgTheme.bodyFont(
                  fontSize: 13,
                  color: isDark
                      ? RpgTheme.timeColorDark
                      : RpgTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final borderColor = FireplaceColors.of(context).convItemBorder;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(8, topClearance, 8, bottomClearance + 8),
      itemCount: friends.length,
      separatorBuilder: (_, index) => Divider(height: 1, color: borderColor),
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _buildContactTile(context, friend);
      },
    );
  }

  Widget _buildContactTile(BuildContext context, UserModel friend) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = friend;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openContactCard(context, user),
        borderRadius: BorderRadius.circular(8),
        splashColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.2),
        child: Padding(
          // Matches ConversationTile metrics exactly (owner: rows must be
          // the same height as the Chats tab): v10 + 44px avatar = 64px.
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AvatarCircle(
                displayName: user.username,
                radius: 22,
                profilePictureUrl: user.profilePictureUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.username,
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
