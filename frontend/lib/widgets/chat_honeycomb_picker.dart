import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/user_model.dart';
import '../theme/glass_theme.dart';
import '../theme/rpg_theme.dart';
import 'glass/glass_sheet.dart';
import 'hex_avatar.dart';

/// Opens the Chats friend picker as floating glass chrome.
Future<UserModel?> showChatHoneycombPicker(
  BuildContext context, {
  required List<UserModel> friends,
}) {
  return showGlassSheet<UserModel>(
    context,
    isScrollControlled: true,
    builder: (_) => ChatHoneycombPicker(friends: friends),
  );
}

/// A one-shot, reduce-motion-aware honeycomb of friends to start a chat with.
class ChatHoneycombPicker extends StatefulWidget {
  const ChatHoneycombPicker({super.key, required this.friends});

  final List<UserModel> friends;

  @override
  State<ChatHoneycombPicker> createState() => _ChatHoneycombPickerState();
}

class _ChatHoneycombPickerState extends State<ChatHoneycombPicker>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 220);

  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: _entranceDuration,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _entranceController,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset =
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Curves.easeOutCubic,
        ),
      );

  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
      return;
    }
    if (!_entranceStarted) {
      _entranceStarted = true;
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _offset,
            child: Padding(
              key: const Key('chat-honeycomb-picker'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: glass.onGlassMuted.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.chatPickerTitle,
                    style: RpgTheme.bodyFont(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.chatPickerSubtitle,
                    style: RpgTheme.bodyFont(
                      fontSize: 13,
                      color: glass.onGlassMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: widget.friends.isEmpty
                        ? _EmptyPickerState(
                            title: l10n.chatPickerEmptyTitle,
                            description: l10n.chatPickerEmptyDescription,
                          )
                        : _HoneycombFriendGrid(
                            friends: widget.friends,
                            onSelected: (friend) =>
                                Navigator.of(context).pop(friend),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoneycombFriendGrid extends StatelessWidget {
  const _HoneycombFriendGrid({required this.friends, required this.onSelected});

  final List<UserModel> friends;
  final ValueChanged<UserModel> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 82).floor().clamp(3, 6);
        final cellHeight =
            (constraints.maxWidth / ((columns + 0.5) * kHexWidthRatio))
                .clamp(64.0, 86.0)
                .toDouble();
        final cellWidth = cellHeight * kHexWidthRatio;
        final rows = (friends.length / columns).ceil();

        return ListView.builder(
          key: const Key('chat-honeycomb-grid'),
          itemCount: rows,
          padding: EdgeInsets.zero,
          itemBuilder: (context, row) {
            final start = row * columns;
            final end = (start + columns).clamp(0, friends.length);
            return SizedBox(
              height: cellHeight * 0.82,
              child: Padding(
                padding: EdgeInsets.only(left: row.isOdd ? cellWidth / 2 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final friend in friends.sublist(start, end))
                      SizedBox(
                        width: cellWidth,
                        height: cellHeight,
                        child: Semantics(
                          button: true,
                          label: friend.displayHandle,
                          child: InkResponse(
                            key: Key('chat-picker-friend-${friend.id}'),
                            onTap: () => onSelected(friend),
                            radius: cellHeight / 2,
                            child: Center(
                              child: HexAvatar(
                                size: cellHeight,
                                displayName: friend.username,
                                imageUrl: friend.profilePictureUrl,
                                surface: colorScheme.surface,
                                borderColor: glass.border,
                                initialsStyle: RpgTheme.bodyFont(
                                  fontSize: cellHeight * 0.25,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
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

class _EmptyPickerState extends StatelessWidget {
  const _EmptyPickerState({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);
    return Center(
      child: Semantics(
        key: const Key('chat-honeycomb-empty-state'),
        container: true,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_outlined, size: 48, color: glass.onGlassMuted),
              const SizedBox(height: 14),
              Text(
                title,
                style: RpgTheme.bodyFont(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: RpgTheme.bodyFont(
                  fontSize: 13,
                  color: glass.onGlassMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
