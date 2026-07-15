import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/friends_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../theme/glass_theme.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/glass/glass_dialog.dart';
import '../widgets/glass/glass_surface.dart';
import '../widgets/glass/glass_menu.dart';
import '../widgets/glass/glass_sheet.dart';
import '../widgets/top_snackbar.dart' show showTopSnackBar;
import 'avatar_crop_screen.dart';
import 'edit_about_screen.dart';

/// Relationship-aware card presentation for a contact or the current user
/// (accepted round-1 direction D1 "Telegram Full-Bleed", 2026-07-15).
///
/// Self cards derive their photos/about LIVE from [AuthProvider] so photo and
/// About edits apply in place — the screen must never pop itself to "refresh"
/// (the pre-rework nav-bounce bug). Other-user cards render the snapshot the
/// entry route assembled.
class UserCardScreen extends StatefulWidget {
  final UserCardVisualData data;
  final VoidCallback? onMessage;
  final ValueChanged<UserCardMute>? onMuteChanged;

  const UserCardScreen({
    super.key,
    required this.data,
    this.onMessage,
    this.onMuteChanged,
  });

  @override
  State<UserCardScreen> createState() => _UserCardScreenState();
}

class _UserCardScreenState extends State<UserCardScreen> {
  /// Hoisted so the pager survives header collapse rebuilds
  /// (flutter/flutter#41157: a controller recreated inside the header
  /// delegate resets to page 0 on every shrinkOffset change).
  final PageController _pageController = PageController();
  int _activePhotoIndex = 0;
  UserCardMute _mute = UserCardMute.off;

  @override
  void initState() {
    super.initState();
    _mute = widget.data.mute;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Self cards re-derive from the live provider; other cards keep the
  /// snapshot assembled by the entry route. Pass `listen: false` from event
  /// handlers/sheet builders — `watch` outside build throws.
  UserCardVisualData _effectiveData(BuildContext context, {bool listen = true}) {
    if (!widget.data.isSelf) return widget.data;
    final user = Provider.of<AuthProvider>(context, listen: listen).currentUser;
    if (user == null) return widget.data;
    return UserCardVisualData.fromUser(
      user,
      isSelf: true,
      hasConversation: widget.data.hasConversation,
      mute: _mute,
    );
  }

  int _clampedIndex(UserCardVisualData data) =>
      data.photos.isEmpty ? 0 : _activePhotoIndex.clamp(0, data.photos.length - 1);

  void _showFeedback(String message) {
    showTopSnackBar(context, message);
  }

  Future<void> _copyHandle(String handle) async {
    await Clipboard.setData(ClipboardData(text: handle));
    if (!mounted) return;
    _showFeedback(AppLocalizations.of(context).userCardCopiedHandle(handle));
  }

  /// Profile mutations must FAIL LOUDLY: a swallowed exception here is how
  /// the broken 201-status check shipped unnoticed (bug-2 postmortem).
  Future<bool> _runProfileAction(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) {
        _showFeedback(e.toString().replaceFirst('Exception: ', ''));
      }
      return false;
    }
  }

  Future<void> _addProfilePhoto() async {
    final auth = context.read<AuthProvider>();
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(imageBytes: bytes, fallback: image),
      ),
    );
    if (cropped == null || !mounted) return;
    if (!await _runProfileAction(() => auth.updateProfilePicture(cropped))) {
      return;
    }
    if (!mounted) return;
    // Jump the pager to the newly added photo (appended after the primary
    // sort) so the change is visible immediately.
    final photos = _effectiveData(context, listen: false).photos;
    if (photos.isNotEmpty && _pageController.hasClients) {
      final target = photos.length - 1;
      _pageController.jumpToPage(target);
      setState(() => _activePhotoIndex = target);
    }
  }

  Future<void> _setPhotoAsPrimary(int photoId) async {
    final auth = context.read<AuthProvider>();
    if (!await _runProfileAction(() => auth.setPrimaryProfilePhoto(photoId))) {
      return;
    }
    if (!mounted) return;
    // Primary sorts first — follow it so "main" state stays visible.
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    setState(() => _activePhotoIndex = 0);
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
        return GlassDialog(
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

  Future<void> _deleteProfilePhoto(int photoId) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirmAction(
      title: l10n.userCardDeletePhotoTitle,
      message: l10n.userCardDeletePhotoConfirm,
      confirmLabel: l10n.delete,
    )) {
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!await _runProfileAction(() => auth.deleteProfilePhoto(photoId))) {
      return;
    }
    if (!mounted) return;
    final photos = _effectiveData(context, listen: false).photos;
    final target = photos.isEmpty ? 0 : _activePhotoIndex.clamp(0, photos.length - 1);
    if (photos.isNotEmpty && _pageController.hasClients) {
      _pageController.jumpToPage(target);
    }
    setState(() => _activePhotoIndex = target);
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

  Future<void> _editAbout(String? currentAbout) async {
    final auth = context.read<AuthProvider>();
    final next = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => EditAboutScreen(initialAbout: currentAbout),
      ),
    );
    if (next == null || !mounted) return;
    final trimmed = next.trim();
    await _runProfileAction(
      () => auth.updateProfileAbout(trimmed.isEmpty ? null : trimmed),
    );
    // Stay on the card — the watched provider refreshes the About section.
  }

  Future<void> _pickMute(BuildContext anchorContext) async {
    final l10n = AppLocalizations.of(anchorContext);
    final selected = await showGlassMenu<UserCardMute>(
      context: anchorContext,
      entries: [
        GlassMenuEntry(
          value: UserCardMute.off,
          child: Text(l10n.userCardNotificationsOn),
        ),
        GlassMenuEntry(
          value: UserCardMute.oneHour,
          child: Text(l10n.userCardMuteOneHour),
        ),
        GlassMenuEntry(
          value: UserCardMute.eightHours,
          child: Text(l10n.userCardMuteEightHours),
        ),
        GlassMenuEntry(
          value: UserCardMute.oneWeek,
          child: Text(l10n.userCardMuteOneWeek),
        ),
        GlassMenuEntry(
          value: UserCardMute.forever,
          child: Text(l10n.userCardMuteForever),
        ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() => _mute = selected);
    widget.onMuteChanged?.call(selected);
  }

  Future<void> _showPhotoSheet(UserCardVisualData data) async {
    await showGlassSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final live = _effectiveData(context, listen: false);
          final photos = live.photos;
          if (photos.isEmpty) {
            // Everything deleted from within the sheet.
            return const SizedBox(height: 80);
          }
          final index = _clampedIndex(live);
          final photo = photos[index];
          final l10n = AppLocalizations.of(sheetContext);
          final theme = Theme.of(sheetContext);
          // Transparent Material so ListTile rows keep ink and don't assert
          // against the glass surface's decorated box (SPEC §11 pattern).
          return Material(
            type: MaterialType.transparency,
            child: SafeArea(
              top: false,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n
                        .userCardPhotoOfCount('${index + 1}', '${photos.length}')
                        .toUpperCase(),
                    style: RpgTheme.bodyFont(
                      fontSize: 11,
                      color: GlassTheme.of(sheetContext).onGlassMuted,
                      fontWeight: FontWeight.w800,
                    ).copyWith(letterSpacing: 0.9),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _PhotoSlot(
                          photo: i < photos.length ? photos[i] : null,
                          selected: i == index,
                          onTap: i < photos.length
                              ? () {
                                  if (_pageController.hasClients) {
                                    _pageController.jumpToPage(i);
                                  }
                                  setState(() => _activePhotoIndex = i);
                                  setSheetState(() {});
                                }
                              : () async {
                                  Navigator.of(sheetContext).pop();
                                  await _addProfilePhoto();
                                },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!photo.isPrimary && photo.id != null)
                    _ActionRow(
                      icon: Icons.star_outline,
                      label: l10n.userCardSetMainPhoto,
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _setPhotoAsPrimary(photo.id!);
                      },
                    ),
                  if (photos.length < 3)
                    _ActionRow(
                      icon: Icons.add_photo_alternate_outlined,
                      label: l10n.userCardAddPhoto,
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _addProfilePhoto();
                      },
                    ),
                  if (photo.id != null)
                    _ActionRow(
                      icon: Icons.delete_outline,
                      label: l10n.userCardDeletePhoto,
                      danger: true,
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _deleteProfilePhoto(photo.id!);
                      },
                    ),
                  if (photo.isPrimary)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.userCardMainPhotoHint,
                        style: RpgTheme.bodyFont(
                          fontSize: 12,
                          color: GlassTheme.of(sheetContext).onGlassMuted,
                        ),
                      ),
                    ),
                  SizedBox(height: theme.platform == TargetPlatform.iOS ? 6 : 2),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _effectiveData(context);
    final hasPhotos = data.photos.isNotEmpty;
    final activeIndex = _clampedIndex(data);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          if (hasPhotos)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ProfileHeroDelegate(
                data: data,
                activeIndex: activeIndex,
                pageController: _pageController,
                topInset: MediaQuery.paddingOf(context).top,
                onPageChanged: (index) =>
                    setState(() => _activePhotoIndex = index),
                onCopy: () => _copyHandle(data.handle),
                onEditPhotos: data.isSelf ? () => _showPhotoSheet(data) : null,
                scaffoldColor: theme.scaffoldBackgroundColor,
                onSurface: theme.colorScheme.onSurface,
              ),
            )
          else
            SliverAppBar(
              pinned: true,
              backgroundColor: theme.scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                tooltip: l10n.userCardBack,
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasPhotos) ...[
                    _CompactIdentity(
                      data: data,
                      onCopy: () => _copyHandle(data.handle),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!data.isSelf) ...[
                    _ActionTilesRow(
                      hasConversation: data.hasConversation,
                      mute: _mute,
                      onMessage: widget.onMessage,
                      onMute: data.hasConversation ? _pickMute : null,
                      onCopy: () => _copyHandle(data.handle),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (data.about != null) ...[
                    _Section(
                      title: l10n.userCardAbout,
                      child: Text(
                        data.about!,
                        style: RpgTheme.bodyFont(
                          fontSize: 15,
                          color: theme.colorScheme.onSurface,
                        ).copyWith(height: 1.35),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (data.isSelf)
                    _Section(
                      title: l10n.userCardMyProfile,
                      child: Column(
                        children: [
                          _ActionRow(
                            icon: Icons.edit_outlined,
                            label: l10n.userCardEditAbout,
                            onTap: () => _editAbout(data.about),
                          ),
                          _ActionRow(
                            icon: Icons.add_photo_alternate_outlined,
                            label: data.photos.length < 3
                                ? l10n.userCardAddPhoto
                                : l10n.userCardPhotoLimitReached,
                            detail: '${data.photos.length}/3',
                            onTap:
                                data.photos.length < 3 ? _addProfilePhoto : null,
                          ),
                          if (hasPhotos)
                            _ActionRow(
                              icon: Icons.photo_library_outlined,
                              label: l10n.userCardManagePhotos,
                              onTap: () => _showPhotoSheet(data),
                            ),
                        ],
                      ),
                    ),
                  if (!data.isSelf && data.userId != null)
                    _Section(
                      title: l10n.userCardSafety,
                      child: Column(
                        children: [
                          _ActionRow(
                            icon: Icons.person_remove_outlined,
                            label: l10n.userCardRemoveContact,
                            danger: true,
                            onTap: _removeContact,
                          ),
                          _ActionRow(
                            icon: Icons.block_outlined,
                            label: l10n.block,
                            danger: true,
                            onTap: _blockContact,
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
  final UserCardMute mute;

  factory UserCardVisualData.fromUser(
    UserModel user, {
    required bool isSelf,
    required bool hasConversation,
    UserCardMute mute = UserCardMute.off,
  }) {
    final profilePhotos = user.profilePhotos;
    final photos = profilePhotos.isEmpty
        ? (user.profilePictureUrl == null ||
                  user.profilePictureUrl!.trim().isEmpty
              ? const <UserCardPhoto>[]
              : [
                  UserCardPhoto(
                    url: user.profilePictureUrl!,
                    isPrimary: true,
                    semanticLabel: user.displayHandle,
                  ),
                ])
        : profilePhotos
              .map(
                (photo) => UserCardPhoto(
                  id: photo.id,
                  url: photo.url,
                  isPrimary: photo.isPrimary,
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
  final bool isPrimary;
  final String semanticLabel;

  const UserCardPhoto({
    this.id,
    required this.url,
    this.isPrimary = false,
    required this.semanticLabel,
  });
}

/// Collapsing full-bleed photo hero (Telegram-style shrink-to-circle).
///
/// The photo pager fills the header while expanded; past 55% collapse the
/// whole pager morphs (rect + border radius lerp) into a 40px circle sitting
/// where a top-bar avatar would be, and the bar title fades in. The pager
/// stays mounted through the morph so page state survives collapse.
class _ProfileHeroDelegate extends SliverPersistentHeaderDelegate {
  final UserCardVisualData data;
  final int activeIndex;
  final PageController pageController;
  final double topInset;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onCopy;
  final VoidCallback? onEditPhotos;
  final Color scaffoldColor;
  final Color onSurface;

  const _ProfileHeroDelegate({
    required this.data,
    required this.activeIndex,
    required this.pageController,
    required this.topInset,
    required this.onPageChanged,
    required this.onCopy,
    required this.onEditPhotos,
    required this.scaffoldColor,
    required this.onSurface,
  });

  static const double _photoExtent = 300;
  static const double _barHeight = 68;
  static const double _circleSize = 40;

  @override
  double get maxExtent => topInset + _photoExtent;

  @override
  double get minExtent => topInset + _barHeight;

  @override
  bool shouldRebuild(_ProfileHeroDelegate oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.activeIndex != activeIndex ||
      oldDelegate.topInset != topInset ||
      oldDelegate.scaffoldColor != scaffoldColor;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final l10n = AppLocalizations.of(context);
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    // Photo stays full-bleed for the first 55% of the collapse, then morphs
    // into the bar circle over the remaining 45%.
    final morphT = Curves.easeInOut.transform(
      ((t - 0.55) / 0.45).clamp(0.0, 1.0),
    );
    // Overlays (segment strip, name, scrim, edit button) fade out early.
    final heroOpacity = (1 - t / 0.55).clamp(0.0, 1.0);
    // Bar title fades in across the whole morph (review nit: thresholding
    // morphT AGAIN made the title pop in abruptly near full collapse).
    final barOpacity = morphT;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = math.max(minExtent, maxExtent - shrinkOffset);
        final circleTop = topInset + (_barHeight - _circleSize) / 2;
        final photoRect = Rect.lerp(
          Rect.fromLTWH(0, 0, width, height),
          Rect.fromLTWH(66, circleTop, _circleSize, _circleSize),
          morphT,
        )!;
        final radius = lerpDouble(0, _circleSize / 2, morphT)!;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: ColoredBox(color: scaffoldColor)),
            Positioned.fromRect(
              rect: photoRect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: pageController,
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
                              color: Theme.of(context).colorScheme.primary,
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
                    // Edge scrim for status-bar icons and the identity block.
                    // MUST stay pointer-transparent: a full-bleed BoxDecoration
                    // hit-tests as a solid rectangle and would swallow the
                    // pager's horizontal drags (the pre-rework dead-swipe bug).
                    IgnorePointer(
                      child: Opacity(
                        opacity: heroOpacity,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x59000000),
                                Color(0x00000000),
                                Color(0x8A000000),
                              ],
                              stops: [0, 0.42, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (data.photos.length > 1 && heroOpacity > 0)
              Positioned(
                top: topInset + 10,
                left: 76,
                right: 16,
                child: IgnorePointer(
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
              ),
            if (heroOpacity > 0)
              Positioned(
                left: 18,
                right: 12,
                bottom: 14,
                child: Opacity(
                  opacity: heroOpacity,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RpgTheme.bodyFont(
                                fontSize: 23,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              data.handle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RpgTheme.bodyFont(
                                fontSize: 12.5,
                                color: Colors.white.withValues(alpha: 0.78),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.userCardCopyHandle,
                        onPressed: onCopy,
                        color: Colors.white,
                        icon: const Icon(Icons.copy_outlined, size: 20),
                      ),
                      if (onEditPhotos != null)
                        GlassCircle(
                          size: 44,
                          child: Center(
                            child: IconButton(
                              tooltip: l10n.userCardManagePhotos,
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: Colors.white,
                              ),
                              onPressed: onEditPhotos,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // Collapsed bar title next to the shrunken circle avatar.
            if (barOpacity > 0)
              Positioned(
                left: 66 + _circleSize + 10,
                top: circleTop,
                height: _circleSize,
                right: 16,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: barOpacity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        data.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RpgTheme.bodyFont(
                          fontSize: 16,
                          color: onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: topInset + 8,
              left: 14,
              child: GlassCircle(
                size: 52,
                child: Center(
                  child: IconButton(
                    tooltip: l10n.userCardBack,
                    icon: Icon(
                      Icons.arrow_back,
                      color: morphT > 0.5 ? onSurface : Colors.white,
                    ),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
          tooltip: l10n.userCardCopyHandle,
          onPressed: onCopy,
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

/// D1 action tiles: Message / Mute / Copy tag as equal glass-tinted cards.
class _ActionTilesRow extends StatelessWidget {
  final bool hasConversation;
  final UserCardMute mute;
  final VoidCallback? onMessage;
  final void Function(BuildContext anchorContext)? onMute;
  final VoidCallback onCopy;

  const _ActionTilesRow({
    required this.hasConversation,
    required this.mute,
    required this.onMessage,
    required this.onMute,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.chat_bubble_outline,
            label: l10n.userCardMessage,
            onTap: onMessage,
          ),
        ),
        if (onMute != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (tileContext) => _ActionTile(
                icon: mute == UserCardMute.off
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                label: mute == UserCardMute.off
                    ? l10n.userCardMute
                    : l10n.userCardMuted,
                onTap: () => onMute!(tileContext),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.copy_outlined,
            label: l10n.userCardCopyTag,
            onTap: onCopy,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionTile({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FireplaceColors.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.82),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RpgTheme.bodyFont(
                  fontSize: 11.5,
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 64px photo slot in the manage-photos sheet; ring + star = main photo.
class _PhotoSlot extends StatelessWidget {
  final UserCardPhoto? photo;
  final bool selected;
  final VoidCallback onTap;

  const _PhotoSlot({
    required this.photo,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final side = photo != null && photo!.isPrimary
        ? BorderSide(color: accent, width: 2)
        : BorderSide(
            color: selected
                ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                : FireplaceColors.of(context).borderColor,
          );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.fromBorderSide(side),
        ),
        clipBehavior: Clip.antiAlias,
        child: photo == null
            ? Icon(Icons.add, color: FireplaceColors.of(context).mutedText)
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    photo!.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: theme.colorScheme.primary,
                      child: const Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (photo!.isPrimary)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
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
  final String? detail;
  final bool danger;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.detail,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      minVerticalPadding: 0,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: RpgTheme.bodyFont(
          fontSize: 15,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                detail!,
                style: RpgTheme.bodyFont(
                  fontSize: 13,
                  color: color.withValues(alpha: 0.6),
                ),
              ),
            ),
          Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
        ],
      ),
      onTap: onTap,
    );
  }
}
