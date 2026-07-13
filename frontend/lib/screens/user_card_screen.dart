import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/friends_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/chat_background_pattern.dart';
import '../widgets/top_snackbar.dart' show showTopSnackBar;

/// Relationship-aware card presentation for a contact or the current user.
///
/// The entry routes assemble [UserCardVisualData] from the normalized
/// profile, conversation, and locally persisted wallpaper state.
class UserCardScreen extends StatefulWidget {
  final UserCardVisualData data;
  final VoidCallback? onMessage;
  final ValueChanged<UserCardMute>? onMuteChanged;
  final ValueChanged<UserCardWallpaper>? onWallpaperChanged;

  const UserCardScreen({
    super.key,
    required this.data,
    this.onMessage,
    this.onMuteChanged,
    this.onWallpaperChanged,
  });

  @override
  State<UserCardScreen> createState() => _UserCardScreenState();
}

class _UserCardScreenState extends State<UserCardScreen> {
  late int _activePhotoIndex;
  late UserCardWallpaper _wallpaper;
  late UserCardMute _mute;

  @override
  void initState() {
    super.initState();
    _activePhotoIndex = 0;
    _wallpaper = widget.data.wallpaper;
    _mute = widget.data.mute;
  }

  @override
  void didUpdateWidget(UserCardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _activePhotoIndex = 0;
      _wallpaper = widget.data.wallpaper;
      _mute = widget.data.mute;
    }
  }

  bool get _hasPhotos => widget.data.photos.isNotEmpty;

  void _showPreviewFeedback(String message) {
    showTopSnackBar(context, message);
  }

  Future<void> _copyHandle() async {
    await Clipboard.setData(ClipboardData(text: widget.data.handle));
    if (!mounted) return;
    _showPreviewFeedback(
      AppLocalizations.of(context).userCardCopiedHandle(widget.data.handle),
    );
  }

  Future<void> _addProfilePhoto() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    await context.read<AuthProvider>().updateProfilePicture(image);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _setActivePhotoAsPrimary() async {
    final photoId = widget.data.photos[_activePhotoIndex].id;
    if (photoId == null) return;
    await context.read<AuthProvider>().setPrimaryProfilePhoto(photoId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _deleteActiveProfilePhoto() async {
    final photoId = widget.data.photos[_activePhotoIndex].id;
    if (photoId == null) return;
    final l10n = AppLocalizations.of(context);
    if (!await _confirmAction(
      title: l10n.userCardDeletePhotoTitle,
      message: l10n.userCardDeletePhotoConfirm,
      confirmLabel: l10n.delete,
    )) {
      return;
    }
    if (!mounted) return;
    await context.read<AuthProvider>().deleteProfilePhoto(photoId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _removeContact() async {
    final userId = widget.data.userId;
    if (userId == null) return;
    final l10n = AppLocalizations.of(context);
    if (!await _confirmAction(
      title: l10n.removeFriendTitle,
      message: l10n.removeFriendConfirm(widget.data.username),
      confirmLabel: l10n.remove,
    )) {
      return;
    }
    if (!mounted) return;
    context.read<FriendsProvider>().unfriend(userId);
    Navigator.of(context).pop();
  }

  Future<void> _blockContact() async {
    final userId = widget.data.userId;
    if (userId == null) return;
    final l10n = AppLocalizations.of(context);
    if (!await _confirmAction(
      title: l10n.userCardBlockTitle(widget.data.handle),
      message: l10n.userCardBlockConfirm,
      confirmLabel: l10n.block,
    )) {
      return;
    }
    if (!mounted) return;
    context.read<FriendsProvider>().blockUser(userId);
    Navigator.of(context).pop();
  }

  Future<void> _editAbout() async {
    final controller = TextEditingController(text: widget.data.about ?? '');
    final l10n = AppLocalizations.of(context);
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.userCardAbout),
        content: TextField(
          controller: controller,
          maxLength: 80,
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.userCardCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.userCardSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || !mounted) return;
    await context
        .read<AuthProvider>()
        .updateProfileAbout(next.trim().isEmpty ? null : next.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          if (_hasPhotos)
            _PhotoHero(
              data: data,
              activeIndex: _activePhotoIndex,
              onPageChanged: (index) => setState(() => _activePhotoIndex = index),
              onCopy: _copyHandle,
            )
          else
            SliverAppBar(
              pinned: true,
              backgroundColor: theme.scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(

                tooltip: AppLocalizations.of(context).userCardBack,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              ),
              titleSpacing: 0,
              title: Row(
                children: [
                  AvatarCircle(displayName: data.username, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data.handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RpgTheme.bodyFont(
                        fontSize: 16,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_hasPhotos)
                    _CompactIdentity(data: data, onCopy: _copyHandle),
                  if (_hasPhotos) const SizedBox(height: 4),
                  if (data.about != null) ...[
                    const SizedBox(height: 20),
                    _Section(
                      title: AppLocalizations.of(context).userCardAbout,
                      child: Text(
                        data.about!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: RpgTheme.bodyFont(
                          fontSize: 15,
                          color: theme.colorScheme.onSurface,
                        ).copyWith(height: 1.35),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (data.isSelf)
                    _SelfActions(
                      photoCount: data.photos.length,
                      activePhoto: _hasPhotos
                          ? data.photos[_activePhotoIndex]
                          : null,
                      onAddPhoto: _addProfilePhoto,
                      onEditAbout: _editAbout,
                      onSetPrimary: _setActivePhotoAsPrimary,
                      onDelete: _deleteActiveProfilePhoto,
                    )
                  else
                    _ContactActions(
                      hasConversation: data.hasConversation,
                      mute: _mute,
                      onMuteChanged: (mute) {
                        setState(() => _mute = mute);
                        widget.onMuteChanged?.call(mute);
                      },
                      onMessage: widget.onMessage,
                    ),
                  if (!data.isSelf && data.hasConversation) ...[
                    const SizedBox(height: 20),
                    _WallpaperSection(
                      value: _wallpaper,
                      onChanged: (wallpaper) {
                        setState(() => _wallpaper = wallpaper);
                        widget.onWallpaperChanged?.call(wallpaper);
                      },
                    ),
                  ],
                  if (!data.isSelf && data.userId != null) ...[
                    const SizedBox(height: 20),
                    _SafetyActions(
                      onRemoveContact: _removeContact,
                      onBlockContact: _blockContact,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserCardVisualData {
  final int? userId;
  final String username;
  final String tag;
  final String? about;
  final bool isSelf;
  final bool hasConversation;
  final List<UserCardPhoto> photos;
  final UserCardWallpaper wallpaper;
  final UserCardMute mute;

  factory UserCardVisualData.fromUser(
    UserModel user, {
    required bool isSelf,
    required bool hasConversation,
    UserCardWallpaper wallpaper = UserCardWallpaper.defaultBackground,
    UserCardMute mute = UserCardMute.off,
  }) {
    final profilePhotos = user.profilePhotos;
    final photos = profilePhotos.isEmpty
        ? (user.profilePictureUrl == null || user.profilePictureUrl!.trim().isEmpty
            ? const <UserCardPhoto>[]
            : [
                UserCardPhoto(
                  url: user.profilePictureUrl!,
                  semanticLabel: user.displayHandle,
                ),
              ])
        : profilePhotos
            .map(
              (photo) => UserCardPhoto(
                id: photo.id,
                url: photo.url,
                semanticLabel: user.displayHandle,
              ),
            )
            .toList(growable: false);
    return UserCardVisualData(
      userId: user.id,
      username: user.username,
      about: user.about,
      tag: user.tag,
      isSelf: isSelf,
      hasConversation: hasConversation,
      photos: photos,
      wallpaper: wallpaper,
      mute: mute,
    );
  }

  const UserCardVisualData({
    this.userId,
    required this.username,
    required this.tag,
    this.about,
    required this.isSelf,
    required this.hasConversation,
    this.photos = const [],
    this.wallpaper = UserCardWallpaper.defaultBackground,
    this.mute = UserCardMute.off,
  });

  String get handle => '$username#$tag';
}
enum UserCardMute {
  off,
  oneHour,
  eightHours,
  oneWeek,
  forever;

  static UserCardMute fromConversation({
    required bool muted,
    required DateTime? mutedUntil,
    DateTime? now,
  }) {
    if (!muted) return UserCardMute.off;
    if (mutedUntil == null) return UserCardMute.forever;
    final remaining = mutedUntil.difference(now ?? DateTime.now());
    if (remaining <= Duration.zero) return UserCardMute.off;
    if (remaining <= const Duration(hours: 2)) return UserCardMute.oneHour;
    if (remaining <= const Duration(hours: 12)) return UserCardMute.eightHours;
    return UserCardMute.oneWeek;
  }
}
class UserCardPhoto {
  final int? id;
  final String url;
  final String semanticLabel;

  const UserCardPhoto({
    this.id,
    required this.url,
    required this.semanticLabel,
  });
}

enum UserCardWallpaper { defaultBackground, glyphs }


class _PhotoHero extends StatelessWidget {
  final UserCardVisualData data;
  final int activeIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onCopy;

  const _PhotoHero({
    required this.data,
    required this.activeIndex,
    required this.onPageChanged,
    required this.onCopy,
  });

  static const _expandedHeight = 390.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final l10n = AppLocalizations.of(context);
    return SliverAppBar(
      pinned: true,
      expandedHeight: _expandedHeight,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: l10n.userCardBack,
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.maybePop(context),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final toolbarHeight = kToolbarHeight + topInset;
          final collapsed = ((_expandedHeight - constraints.maxHeight) /
                  (_expandedHeight - toolbarHeight))
              .clamp(0.0, 1.0);
          final heroOpacity = 1 - collapsed;

          return Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                itemCount: data.photos.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  final photo = data.photos[index];
                  return Semantics(
                    image: true,
                    label: photo.semanticLabel,
                    child: Image.network(
                      photo.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: theme.colorScheme.primary,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_outlined,
                          size: 54,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x66000000),
                      Color(0x00000000),
                      Color(0xB8000000),
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              if (data.photos.length > 1)
                Positioned(
                  top: topInset + 10,
                  left: 64,
                  right: 16,
                  child: Opacity(
                    opacity: heroOpacity,
                    child: Row(
                      children: List.generate(data.photos.length, (index) {
                        final selected = index == activeIndex;
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: EdgeInsets.only(
                              right: index == data.photos.length - 1 ? 0 : 5,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.36),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                right: 12,
                bottom: 20,
                child: Opacity(
                  opacity: heroOpacity,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RpgTheme.bodyFont(
                            fontSize: 25,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context).userCardCopyHandle,
                        onPressed: onCopy,
                        color: Colors.white,
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: topInset + 8,
                left: 64,
                right: 16,
                child: IgnorePointer(
                  ignoring: collapsed < 0.95,
                  child: Opacity(
                    opacity: collapsed,
                    child: Row(
                      children: [
                        AvatarCircle(
                          displayName: data.username,
                          radius: 17,
                          profilePictureUrl: data.photos.first.url,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            data.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RpgTheme.bodyFont(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompactIdentity extends StatelessWidget {
  final UserCardVisualData data;
  final VoidCallback onCopy;

  const _CompactIdentity({required this.data, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        AvatarCircle(displayName: data.username, radius: 34),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RpgTheme.bodyFont(
                  fontSize: 20,
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.userCardNoProfilePhoto,
                style: RpgTheme.bodyFont(fontSize: 13, color: colors.mutedText),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).userCardCopyHandle,
          onPressed: onCopy,
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

class _ContactActions extends StatelessWidget {
  final bool hasConversation;
  final UserCardMute mute;
  final ValueChanged<UserCardMute> onMuteChanged;
  final VoidCallback? onMessage;

  const _ContactActions({
    required this.hasConversation,
    required this.mute,
    required this.onMuteChanged,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onMessage,
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(
            hasConversation ? l10n.userCardTypeMessage : l10n.userCardMessage,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: RpgTheme.bodyFont(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (hasConversation) ...[
          const SizedBox(height: 10),
          _Section(
            title: l10n.userCardNotifications,
            child: Row(
              children: [
                Icon(
                  mute == UserCardMute.off
                      ? Icons.notifications_outlined
                      : Icons.notifications_off_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _muteLabel(l10n, mute),
                    style: RpgTheme.bodyFont(
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                PopupMenuButton<UserCardMute>(
                  tooltip: l10n.userCardNotifications,
                  onSelected: onMuteChanged,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: UserCardMute.off,
                      child: Text(l10n.userCardNotificationsOn),
                    ),
                    PopupMenuItem(
                      value: UserCardMute.oneHour,
                      child: Text(l10n.userCardMuteOneHour),
                    ),
                    PopupMenuItem(
                      value: UserCardMute.eightHours,
                      child: Text(l10n.userCardMuteEightHours),
                    ),
                    PopupMenuItem(
                      value: UserCardMute.oneWeek,
                      child: Text(l10n.userCardMuteOneWeek),
                    ),
                    PopupMenuItem(
                      value: UserCardMute.forever,
                      child: Text(l10n.userCardMuteForever),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SelfActions extends StatelessWidget {
  final int photoCount;
  final UserCardPhoto? activePhoto;
  final Future<void> Function() onAddPhoto;
  final Future<void> Function() onSetPrimary;
  final Future<void> Function() onDelete;
  final Future<void> Function() onEditAbout;

  const _SelfActions({
    required this.photoCount,
    required this.activePhoto,
    required this.onAddPhoto,
    required this.onSetPrimary,
    required this.onDelete,
    required this.onEditAbout,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Section(
      title: l10n.userCardMyProfile,
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.edit_outlined,
            label: l10n.userCardEditAbout,
            onTap: onEditAbout,
          ),
          _ActionRow(
            icon: Icons.add_photo_alternate_outlined,
            label: photoCount < 3
                ? l10n.userCardAddPhoto
                : l10n.userCardPhotoLimitReached,
            onTap: photoCount < 3 ? onAddPhoto : null,
          ),
          if (activePhoto?.id != null)
            _ActionRow(
              icon: Icons.star_outline,
              label: l10n.userCardSetMainPhoto,
              onTap: onSetPrimary,
            ),
          if (activePhoto?.id != null)
            _ActionRow(
              icon: Icons.delete_outline,
              label: l10n.userCardDeletePhoto,
              danger: true,
              onTap: onDelete,
            ),
        ],
      ),
    );
  }
}

class _WallpaperSection extends StatelessWidget {
  final UserCardWallpaper value;
  final ValueChanged<UserCardWallpaper> onChanged;

  const _WallpaperSection({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);
    return _Section(
      title: l10n.userCardChatBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<UserCardWallpaper>(
            segments: [
              ButtonSegment(
                value: UserCardWallpaper.defaultBackground,
                label: Text(l10n.userCardDefaultBackground),
                icon: const Icon(Icons.rectangle_outlined),
              ),
              ButtonSegment(
                value: UserCardWallpaper.glyphs,
                label: Text(l10n.userCardGlyphsBackground),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.single),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 104,
              child: value == UserCardWallpaper.glyphs
                  ? ChatBackgroundPattern(
                      backgroundColor: colors.messagesAreaBg,
                      child: const _ConversationPreview(),
                    )
                  : ColoredBox(
                      color: colors.messagesAreaBg,
                      child: const _ConversationPreview(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.userCardBackgroundPrivate,
            style: RpgTheme.bodyFont(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyActions extends StatelessWidget {
  final Future<void> Function() onRemoveContact;
  final Future<void> Function() onBlockContact;

  const _SafetyActions({
    required this.onRemoveContact,
    required this.onBlockContact,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Section(
      title: l10n.userCardSafety,
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.person_remove_outlined,
            label: l10n.userCardRemoveContact,
            danger: true,
            onTap: onRemoveContact,
          ),
          _ActionRow(
            icon: Icons.block_outlined,
            label: l10n.block,
            danger: true,
            onTap: onBlockContact,
          ),
        ],
      ),
    );
  }
}

class _ConversationPreview extends StatelessWidget {
  const _ConversationPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF3C7D6E),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              AppLocalizations.of(context).userCardBackgroundPreviewMessage,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}


class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FireplaceColors.of(context);
    final borderRadius = BorderRadius.circular(18);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.82),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: colors.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: RpgTheme.bodyFont(
                fontSize: 11,
                color: colors.mutedText,
                fontWeight: FontWeight.w800,
              ).copyWith(letterSpacing: 0.9),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      minVerticalPadding: 0,
      leading: Icon(icon, color: color),
      title: Text(label, style: RpgTheme.bodyFont(fontSize: 15, color: color, fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
      onTap: onTap,
    );
  }
}

String _muteLabel(AppLocalizations l10n, UserCardMute mute) {
  return mute == UserCardMute.off
      ? l10n.userCardNotificationsOn
      : l10n.userCardNotificationsMuted;
}
