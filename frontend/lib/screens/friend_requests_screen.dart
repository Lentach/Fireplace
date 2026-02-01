import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  bool _navigatingToChat = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().fetchFriendRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final cardBg = isDark ? RpgTheme.convItemBg : RpgTheme.convItemBgLight;
    final borderColor = isDark ? RpgTheme.border : RpgTheme.convItemBorderLight;
    final textColor = colorScheme.onSurface;
    final secondaryColor =
        isDark ? RpgTheme.border : RpgTheme.textSecondaryLight;

    // Listen for pending open conversation to navigate
    final pendingId = chat.consumePendingOpen();
    if (pendingId != null && !_navigatingToChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigatingToChat = true;
          Navigator.of(context).pop(pendingId);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Friend Requests',
          style: RpgTheme.pressStart2P(fontSize: 14),
        ),
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatConsumer, _) {
          if (chatConsumer.friendRequests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_add_disabled,
                    size: 64,
                    color: secondaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pending requests',
                    style: RpgTheme.bodyFont(
                      fontSize: 16,
                      color: secondaryColor,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: chatConsumer.friendRequests.length,
            itemBuilder: (context, index) {
              final request = chatConsumer.friendRequests[index];
              final displayName = request.sender.username ?? request.sender.email;
              final firstLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: colorScheme.primary,
                            child: Text(
                              firstLetter,
                              style: RpgTheme.bodyFont(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Name and text
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: RpgTheme.bodyFont(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'wants to add you as a friend',
                                  style: RpgTheme.bodyFont(
                                    fontSize: 12,
                                    color: secondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Accept button
                          ElevatedButton.icon(
                            onPressed: () {
                              context.read<ChatProvider>().acceptFriendRequest(request.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Friend added: $displayName'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Accept'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          // Reject button
                          ElevatedButton.icon(
                            onPressed: () {
                              context.read<ChatProvider>().rejectFriendRequest(request.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Request rejected'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
