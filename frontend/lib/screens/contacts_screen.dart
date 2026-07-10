import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/user_model.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/glass/glass_sheet.dart';
import '../widgets/main_tab_screen_header.dart';
import '../utils/instant_opaque_route.dart';
import 'chat_detail_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

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

  void _showContactContextMenu(BuildContext context, UserModel user) {
    final colorScheme = Theme.of(context).colorScheme;

    showGlassSheet<void>(
      context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.person_remove, color: colorScheme.error),
                  title: Text(
                    AppLocalizations.of(
                      context,
                    ).removeFriendTitle.replaceAll('?', ''),
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _unfriendContact(context, user.id, user.username);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.block, color: colorScheme.error),
                  title: Text(
                    AppLocalizations.of(context).block,
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.read<FriendsProvider>().blockUser(user.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _unfriendContact(BuildContext context, int userId, String username) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final mutedColor = FireplaceColors.of(dialogContext).mutedText;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(
            l10n.removeFriendTitle,
            style: RpgTheme.bodyFont(
              fontSize: 16,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            l10n.removeFriendConfirm(username),
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                l10n.cancel,
                style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.read<FriendsProvider>().unfriend(userId);
              },
              child: Text(
                l10n.remove,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
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
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(child: _buildContactsList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return MainTabScreenHeader(title: AppLocalizations.of(context).contacts);
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

    final bottomClearance = MediaQuery.paddingOf(context).bottom;

    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + bottomClearance),
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
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottomClearance + 8),
      itemCount: friends.length,
      separatorBuilder: (_, index) => Divider(height: 1, color: borderColor),
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _buildContactTile(context, friend);
      },
    );
  }

  Widget _buildContactTile(BuildContext context, dynamic friend) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = friend as UserModel;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openChatWithContact(context, user.id),
        onLongPress: () => _showContactContextMenu(context, user),
        borderRadius: BorderRadius.circular(8),
        splashColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              AvatarCircle(
                displayName: user.username,
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
