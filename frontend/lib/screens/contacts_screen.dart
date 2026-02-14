import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import 'chat_detail_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  void _openChatWithContact(BuildContext context, int userId, String email) {
    final chat = context.read<ChatProvider>();

    // Check if conversation exists for this user
    final existingConv = chat.conversations.where((conv) {
      final otherUser = chat.getOtherUser(conv);
      return otherUser?.id == userId;
    }).firstOrNull;

    if (existingConv != null) {
      // Conversation exists, open it
      chat.openConversation(existingConv.id);

      final width = MediaQuery.of(context).size.width;
      if (width < AppConstants.layoutBreakpointDesktop) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(conversationId: existingConv.id),
          ),
        );
      }
    } else {
      // No conversation, start new one (backend will create)
      chat.socket.startConversation(email);
      // consumePendingOpen will handle navigation when backend responds
    }
  }

  void _unfriendContact(BuildContext context, int userId, String username) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final isDark = RpgTheme.isDark(dialogContext);
        final mutedColor =
            isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(
            'Remove Friend?',
            style: RpgTheme.bodyFont(
              fontSize: 16,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Remove $username from your contacts? This will delete all conversation history.',
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.read<ChatProvider>().unfriend(userId);
              },
              child: Text(
                'Remove',
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
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildContactsList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = RpgTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? RpgTheme.convItemBorderDark
                : RpgTheme.convItemBorderLight,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Text(
            'Contacts',
            style: RpgTheme.pressStart2P(
              fontSize: 12,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsList(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final friends = chat.friends;
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: mutedColor),
              const SizedBox(height: 16),
              Text(
                'No contacts yet',
                style: RpgTheme.bodyFont(fontSize: 16, color: mutedColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Add friends to start chatting',
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

    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: friends.length,
      separatorBuilder: (_, index) => Divider(
        height: 1,
        color: borderColor,
      ),
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _buildContactTile(context, friend);
      },
    );
  }

  Widget _buildContactTile(BuildContext context, dynamic friend) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    final username = friend.username ?? friend.email;
    final email = friend.email as String;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openChatWithContact(context, friend.id, email),
        onLongPress: () => _unfriendContact(context, friend.id, username),
        borderRadius: BorderRadius.circular(8),
        splashColor: RpgTheme.primaryColor(context).withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              AvatarCircle(
                email: email,
                profilePictureUrl: friend.profilePictureUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: RpgTheme.bodyFont(
                        fontSize: 13,
                        color: secondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
