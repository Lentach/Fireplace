import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/connection_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import '../theme/rpg_theme.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass/glass_surface.dart';
import '../widgets/top_snackbar.dart';

/// Single screen with tabs: Add user, Friend requests.
class AddOrInvitationsScreen extends StatelessWidget {
  const AddOrInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final topInset = MediaQuery.paddingOf(context).top;
          const rowHeight = 52.0;
          const tabHeight = 54.0;
          final headerHeight = topInset + 8 + rowHeight + 8 + tabHeight + 8;
          return Scaffold(
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                // Tab content clears the floating header. These tabs are a
                // short form + a request list, so a padded (not scroll-behind)
                // body is fine here.
                Padding(
                  padding: EdgeInsets.only(top: headerHeight),
                  child: const TabBarView(
                    children: [_AddByUsernameTab(), _FriendRequestsTab()],
                  ),
                ),
                // Floating glass chrome: back circle + title pill + an inset
                // tab capsule — bounded pills per SPEC §1/§5, never a band.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(14, topInset + 8, 14, 0),
                    child: Column(
                      children: [
                        SizedBox(
                          height: rowHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 60,
                                  ),
                                  child: Center(
                                    child: GlassPill(
                                      height: rowHeight,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: Center(
                                        child: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).addInvitations,
                                          style: RpgTheme.bodyFont(
                                            fontSize: 16,
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: GlassCircle(
                                  size: rowHeight,
                                  child: Center(
                                    child: IconButton(
                                      icon: const Icon(Icons.arrow_back),
                                      tooltip: MaterialLocalizations.of(
                                        context,
                                      ).backButtonTooltip,
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        GlassPill(
                          height: tabHeight,
                          padding: const EdgeInsets.all(4),
                          child: TabBar(
                            indicator: BoxDecoration(
                              color: glass.activeCapsule,
                              borderRadius: BorderRadius.circular(
                                (tabHeight - 8) / 2,
                              ),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            labelColor: glass.onGlassAccent,
                            unselectedLabelColor: glass.onGlassMuted,
                            labelStyle: RpgTheme.bodyFont(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            tabs: [
                              Tab(text: AppLocalizations.of(context).addUser),
                              Tab(
                                child: Consumer<FriendsProvider>(
                                  builder: (context, friends, _) => Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        ).friendRequests,
                                      ),
                                      if (friends.pendingRequestsCount > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 18,
                                          ),
                                          child: Text(
                                            friends.pendingRequestsCount > 99
                                                ? '99+'
                                                : '${friends.pendingRequestsCount}',
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
  bool _handling = false;

  FriendsProvider? _friends;
  ConversationsProvider? _convs;
  ConnectionProvider? _conn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final friends = context.read<FriendsProvider>();
    final convs = context.read<ConversationsProvider>();
    final conn = context.read<ConnectionProvider>();
    if (friends == _friends && convs == _convs && conn == _conn) return;
    _friends?.removeListener(_onProvidersChanged);
    _convs?.removeListener(_onProvidersChanged);
    _conn?.removeListener(_onProvidersChanged);
    _friends = friends;
    _convs = convs;
    _conn = conn;
    _friends!.addListener(_onProvidersChanged);
    _convs!.addListener(_onProvidersChanged);
    _conn!.addListener(_onProvidersChanged);
    // Catch state already pending before this tab mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onProvidersChanged());
  }

  /// Provider-driven side effects (navigation, auto-send, snackbar). Kept OUT of
  /// build(): these notifications originate from socket handlers, so acting here
  /// is safe and build() stays pure. Consume-once flags fire on the notify that
  /// set them.
  void _onProvidersChanged() {
    if (!mounted || _handling) return;
    _handling = true;
    try {
      final convs = _convs!;
      final friends = _friends!;
      final conn = _conn!;

      final pendingId = convs.consumePendingOpen();
      if (pendingId != null) {
        Navigator.of(context).pop(pendingId);
        return;
      }

      if (friends.consumeFriendRequestSent() && !_requestSent) {
        _requestSent = true;
        if (_loading) setState(() => _loading = false);
        final displayHandle = _handleController.text.trim();
        showTopSnackBar(
          context,
          AppLocalizations.of(context).friendRequestSentTo(displayHandle),
          backgroundColor: Colors.green,
        );
        Navigator.pop(context);
        return;
      }

      if (_loading &&
          (conn.errorMessage != null || friends.searchResults != null)) {
        final results = friends.searchResults;
        setState(() => _loading = false);
        // Auto-send when the search resolves to exactly one user.
        // clearSearchResults() notifies synchronously and re-enters this
        // callback; the _handling guard makes that re-entry a no-op.
        if (results != null && results.length == 1) {
          friends.sendFriendRequest(results.first.id);
          friends.clearSearchResults();
        }
      }
    } finally {
      _handling = false;
    }
  }

  @override
  void dispose() {
    _friends?.removeListener(_onProvidersChanged);
    _convs?.removeListener(_onProvidersChanged);
    _conn?.removeListener(_onProvidersChanged);
    _handleController.dispose();
    super.dispose();
  }

  void _search() {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) return;

    setState(() {
      _loading = true;
      _requestSent = false;
    });
    context.read<FriendsProvider>().clearSearchResults();
    context.read<FriendsProvider>().searchUsers(handle);
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsProvider>();
    final conn = context.watch<ConnectionProvider>();
    final searchResults = friends.searchResults;
    final errorMessage = conn.errorMessage;
    final showButtonLoading =
        _loading && errorMessage == null && searchResults == null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSurface(
              borderRadius: BorderRadius.circular(16),
              blur: false,
              shadow: false,
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.of(context).addNewUserHint,
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
                hintText: AppLocalizations.of(context).usernameTagPlaceholder,
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
                  : Text(AppLocalizations.of(context).addNewUser),
            ),
            if (searchResults != null &&
                searchResults.isEmpty &&
                !_loading &&
                errorMessage == null) ...[
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).userNotFound,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                errorMessage,
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
  ConversationsProvider? _convs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadFriendRequests();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final convs = context.read<ConversationsProvider>();
    if (convs == _convs) return;
    _convs?.removeListener(_onConversationsChanged);
    _convs = convs;
    _convs!.addListener(_onConversationsChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _onConversationsChanged());
  }

  /// Navigate on a pending-open conversation. Out of build(): the notify comes
  /// from the socket handler, so popping here is safe.
  void _onConversationsChanged() {
    if (!mounted || _navigatingToChat) return;
    final pendingId = _convs!.consumePendingOpen();
    if (pendingId != null) {
      _navigatingToChat = true;
      Navigator.of(context).pop(pendingId);
    }
  }

  @override
  void dispose() {
    _convs?.removeListener(_onConversationsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final secondaryColor = isDark
        ? RpgTheme.mutedDarkGray
        : RpgTheme.textSecondaryLight;

    return Consumer<FriendsProvider>(
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
                  AppLocalizations.of(context).noPendingRequests,
                  style: RpgTheme.bodyFont(fontSize: 16, color: secondaryColor),
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
            final firstLetter = displayName.isNotEmpty
                ? displayName[0].toUpperCase()
                : '?';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(16),
                blur: false,
                shadow: false,
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
                                AppLocalizations.of(
                                  context,
                                ).wantsToAddYouAsFriend,
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
                            context.read<FriendsProvider>().acceptFriendRequest(
                              request.id,
                            );
                            showTopSnackBar(
                              context,
                              AppLocalizations.of(
                                context,
                              ).friendAdded(displayName),
                              backgroundColor: Colors.green,
                            );
                          },
                          icon: const Icon(Icons.check),
                          label: Text(AppLocalizations.of(context).accept),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            context.read<FriendsProvider>().rejectFriendRequest(
                              request.id,
                            );
                            showTopSnackBar(
                              context,
                              AppLocalizations.of(context).requestRejected,
                              backgroundColor: Colors.red,
                            );
                          },
                          icon: const Icon(Icons.close),
                          label: Text(AppLocalizations.of(context).reject),
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
