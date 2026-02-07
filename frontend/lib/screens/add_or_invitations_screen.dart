import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/top_snackbar.dart';

/// Single screen with tabs: Add by email, Friend requests.
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
            tabs: const [
              Tab(text: 'Add by email'),
              Tab(text: 'Friend requests'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AddByEmailTab(),
            _FriendRequestsTab(),
          ],
        ),
      ),
    );
  }
}

class _AddByEmailTab extends StatefulWidget {
  const _AddByEmailTab();

  @override
  State<_AddByEmailTab> createState() => _AddByEmailTabState();
}

class _AddByEmailTabState extends State<_AddByEmailTab> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _requestSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _startChat() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _loading = true;
      _requestSent = false;
    });
    context.read<ChatProvider>().clearError();
    context.read<ChatProvider>().sendFriendRequest(email);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    // Listen for pending open conversation to navigate (mutual auto-accept)
    final pendingId = chat.consumePendingOpen();
    if (pendingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(pendingId);
        }
      });
    }

    // Listen for server confirmation that friend request was sent
    if (chat.consumeFriendRequestSent() && _loading && !_requestSent) {
      _requestSent = true;
      _loading = false;
      final email = _emailController.text.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showTopSnackBar(context, 'Friend request sent to $email', backgroundColor: Colors.green);
          Navigator.pop(context);
        }
      });
    }

    // Reset loading on error
    if (chat.errorMessage != null && _loading) {
      _loading = false;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the email of the person you want to add:',
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: RpgTheme.rpgInputDecoration(
                hintText: 'user@example.com',
                prefixIcon: Icons.email_outlined,
                context: context,
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              onSubmitted: (_) => _startChat(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _startChat,
              child: _loading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : const Text('Send Friend Request'),
            ),
            if (chat.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                chat.errorMessage!,
                style: RpgTheme.bodyFont(
                    fontSize: 13, color: RpgTheme.errorColor),
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
    final cardBg = isDark ? RpgTheme.convItemBgDark : colorScheme.surface;
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
            final displayName = request.sender.username ?? request.sender.email;
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
