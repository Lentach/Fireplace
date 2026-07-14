import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user_model.dart';
import '../providers/friends_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/glass/glass_top_bar.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsProvider>();
    final blocked = friends.blockedUsers;
    final theme = Theme.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor = isDark
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;
    final media = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context).blocked,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: blocked.isEmpty
          ? Padding(
              padding: EdgeInsets.only(
                top: media.top + GlassTopBar.capsuleHeight + 16,
                bottom: media.bottom,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 48, color: mutedColor),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context).noBlockedUsers,
                        style: RpgTheme.bodyFont(
                          fontSize: 16,
                          color: mutedColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                8,
                media.top + GlassTopBar.capsuleHeight + 16,
                8,
                media.bottom + 8,
              ),
              itemCount: blocked.length,
              separatorBuilder: (_, _) => Divider(
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
    final friendsProvider = context.read<FriendsProvider>();
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
            onPressed: () => friendsProvider.unblockUser(user.id),
            child: Text(
              AppLocalizations.of(context).unblock,
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
