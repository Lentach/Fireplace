import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final blocked = chat.blockedUsers;
    final theme = Theme.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Blocked',
          style: RpgTheme.pressStart2P(
            fontSize: 12,
            color: theme.colorScheme.primary,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.primary),
      ),
      body: blocked.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 48, color: mutedColor),
                    const SizedBox(height: 16),
                    Text(
                      'No blocked users',
                      style: RpgTheme.bodyFont(fontSize: 16, color: mutedColor),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              itemCount: blocked.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: FireplaceColors.of(context).convItemBorder,
              ),
              itemBuilder: (context, index) {
                final user = blocked[index];
                return _BlockedUserTile(user: user);
              },
            ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  final UserModel user;

  const _BlockedUserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chat = context.read<ChatProvider>();
    final displayHandle = user.displayHandle;

    return Padding(
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
              displayHandle,
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => chat.unblockUser(user.id),
            child: Text(
              'Unblock',
              style: RpgTheme.bodyFont(
                fontSize: 13,
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
