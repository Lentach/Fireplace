import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/top_snackbar.dart';

/// Single screen with tabs: Add user, Friend requests.
class AddOrInvitationsScreen extends StatelessWidget {
  const AddOrInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Add / Invitations',
            style: RpgTheme.bodyFont(
              fontSize: 18,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Add user'),
              Tab(
                child: Consumer<ChatProvider>(
                  builder: (context, chat, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Friend requests'),
                      if (chat.pendingRequestsCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            chat.pendingRequestsCount > 99
                                ? '99+'
                                : '${chat.pendingRequestsCount}',
                            style: RpgTheme.bodyFont(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AddByUsernameTab(),
            _FriendRequestsTab(),
          ],
        ),
      ),
    );
  }
}

class _AddByUsernameTab extends StatefulWidget {
  const _AddByUsernameTab();

  @override
  State<_AddByUsernameTab> createState() => _AddByUsernameTabState();
}

class _AddByUsernameTabState extends State<_AddByUsernameTab> {
  final _handleController = TextEditingController();
  bool _loading = false;
  bool _requestSent = false;
  bool _loadingResetScheduled = false;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  void _search() {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) return;

    setState(() {
      _loading = true;
      _requestSent = false;
      _loadingResetScheduled = false;
    });
    context.read<ChatProvider>().clearError();
    context.read<ChatProvider>().clearSearchResults();
    context.read<ChatProvider>().searchUsers(handle);
  }

  void _sendRequestTo(int recipientId, String displayHandle) {
    context.read<ChatProvider>().sendFriendRequest(recipientId);
    showTopSnackBar(
      context,
      'Friend request sent to $displayHandle',
      backgroundColor: Colors.green,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final searchResults = chat.searchResults;

    final pendingId = chat.consumePendingOpen();
    if (pendingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(pendingId);
      });
    }

    if (chat.consumeFriendRequestSent() && _loading && !_requestSent) {
      _requestSent = true;
      _loading = false;
      final displayHandle = _handleController.text.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showTopSnackBar(
            context,
            'Friend request sent to $displayHandle',
            backgroundColor: Colors.green,
          );
          Navigator.pop(context);
        }
      });
    }

    final showButtonLoading =
        _loading && chat.errorMessage == null && searchResults == null;

    if ((chat.errorMessage != null || searchResults != null) &&
        _loading &&
        !_loadingResetScheduled) {
      _loadingResetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loading = false);
      });
    }

    // Auto-send when exactly one result
    if (searchResults != null && searchResults.length == 1 && _loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final user = searchResults.first;
          context.read<ChatProvider>().sendFriendRequest(user.id);
          context.read<ChatProvider>().clearSearchResults();
        }
      });
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'Add new user by username#tag (e.g. username#1234). Your #tag is in Settings, next to your nickname. Each #tag is unique.',
                style: RpgTheme.bodyFont(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _handleController,
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: RpgTheme.rpgInputDecoration(
                hintText: 'username#1234',
                prefixIcon: Icons.person_outlined,
                context: context,
              ),
              autofocus: true,
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: showButtonLoading ? null : _search,
              child: showButtonLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : const Text('Add new user'),
            ),
            if (searchResults != null && searchResults.isEmpty && !_loading) ...[
              const SizedBox(height: 16),
              Text(
                'User not found',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (chat.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                chat.errorMessage!,
                style: RpgTheme.bodyFont(
                  fontSize: 13,
                  color: RpgTheme.errorColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FriendRequestsTab extends StatefulWidget {
  const _FriendRequestsTab();

  @override
  State<_FriendRequestsTab> createState() => _FriendRequestsTabState();
}

class _FriendRequestsTabState extends State<_FriendRequestsTab> {
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
    final cardBg = FireplaceColors.of(context).convItemBg;
    final borderColor = isDark
        ? RpgTheme.borderDark
        : colorScheme.outline.withValues(alpha: 0.5);
    final textColor = colorScheme.onSurface;
    final secondaryColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

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

    return Consumer<ChatProvider>(
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
            final displayName = request.sender.displayHandle;
            final firstLetter =
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            context
                                .read<ChatProvider>()
                                .acceptFriendRequest(request.id);
                            showTopSnackBar(context, 'Friend added: $displayName', backgroundColor: Colors.green);
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            context
                                .read<ChatProvider>()
                                .rejectFriendRequest(request.id);
                            showTopSnackBar(context, 'Request rejected', backgroundColor: Colors.red);
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
    );
  }
}
