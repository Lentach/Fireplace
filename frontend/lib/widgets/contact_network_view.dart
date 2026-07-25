import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../models/user_model.dart';
import '../theme/rpg_theme.dart';
import 'hex_avatar.dart';

/// A provider-free rendering of the existing contact set as a "honeycomb
/// core": the local user's reticle node feeds a fixed-width staggered field
/// of hex terminals that grows straight down and scrolls.
///
/// Composition contract (owner-approved 2026-07-23):
/// - Alphabetical (natural) order = spatial order, rows fill 4-3-4-3, the
///   partial last row centers itself, so the picture never degrades with
///   count - more contacts only means more rows.
/// - Every hex carries its own socket stub + pad (doubled = a real
///   conversation exists). No shared bus wiring: every drawn line is one
///   direct user->contact relationship.
/// - Tapping a contact fills their route with the accent color from the hex
///   up to the local core, then the parent opens the user card.
///
/// The parent owns contact data and navigation.
class ContactNetworkView extends StatefulWidget {
  const ContactNetworkView({
    super.key,
    required this.contacts,
    required this.localNodeLabel,
    this.localNodeAvatarUrl,
    required this.localNodeCaption,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onContactTap,
    this.onContactOpenChat,
    this.openChatSemanticHint,
    this.onAddContact,
    this.addSlotLabel,
    this.addSlotSemanticLabel,
    this.pendingRequestCount = 0,
    this.onPendingRequestsTap,
    this.pendingRequestsSemanticLabel,
    required this.networkSemanticLabel,
    required this.localNodeSemanticLabel,
    this.safeInsets = EdgeInsets.zero,
    this.conversationContactIds = const <int>{},
    this.mapCaption,
  });

  final List<UserModel> contacts;
  final String localNodeLabel;

  /// The local user's avatar, shown inside the core reticle when set.
  final String? localNodeAvatarUrl;
  final String localNodeCaption;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<UserModel> onContactTap;

  /// Secondary activation (long press, Shift+Enter): jump straight into the
  /// conversation, no route animation — chat entry is instant by doctrine.
  /// Null for contacts the parent has no conversation for, so a stray press
  /// can never create one; those fall back to [onContactTap].
  final ValueChanged<UserModel>? onContactOpenChat;

  /// Screen-reader hint for the long-press action ("Open chat"), so the
  /// gesture is announced with its meaning instead of a bare "long press".
  final String? openChatSemanticHint;

  /// Tapping the trailing "+" cell. Null hides the cell entirely.
  final VoidCallback? onAddContact;

  /// Caption under the "+" cell (localized by the parent).
  final String? addSlotLabel;

  /// Spoken name of the "+" cell; the visible caption is a bare "add".
  final String? addSlotSemanticLabel;

  /// Inbound friend requests waiting at the core. 0 hides the port.
  final int pendingRequestCount;
  final VoidCallback? onPendingRequestsTap;
  final String? pendingRequestsSemanticLabel;
  final String networkSemanticLabel;
  final String localNodeSemanticLabel;

  /// Parent chrome clearance, such as the floating tab header and navigation.
  final EdgeInsets safeInsets;

  /// Ids of contacts that already share a conversation with the local user.
  /// Their socket renders doubled. Purely visual; the parent supplies real data.
  final Set<int> conversationContactIds;

  /// Factual micro-caption under the bottom-left frame bracket (node count).
  final String? mapCaption;

  @override
  State<ContactNetworkView> createState() => _ContactNetworkViewState();
}

class _ContactNetworkViewState extends State<ContactNetworkView>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  late final AnimationController _routeController;

  int? _routeContactId;
  int? _focusedContactId;
  bool _entranceCompleted = false;
  bool _addSlotFocused = false;

  /// Highest row whose avatars may fetch. A ValueNotifier, not setState:
  /// crossing a row while scrolling must rebuild N tiny avatar leaves, not
  /// N Focus/Semantics/GestureDetector/ClipPath subtrees.
  final _armedThroughRow = ValueNotifier<int>(0);

  /// Rows visible right now, recomputed each build. Combined with the
  /// notifier's high-water mark so scrolling back up never drops a face
  /// that already loaded back to initials.
  int _armedFloor = 0;
  ContactHexLayoutResult? _lastLayout;

  @override
  void initState() {
    super.initState();
    _routeController =
        AnimationController(
          vsync: this,
          // Slow enough to READ: the strip travelling to the core is the
          // point of the interaction (owner call, overrides the entrance
          // cap - this is user-triggered feedback, not chrome).
          duration: const Duration(milliseconds: 480),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          final id = _routeContactId;
          _routeController.reset();
          if (id == null) return;
          UserModel? target;
          for (final contact in widget.contacts) {
            if (contact.id == id) {
              target = contact;
              break;
            }
          }
          setState(() => _routeContactId = null);
          if (target != null) widget.onContactTap(target);
        });
    _scrollController.addListener(_armVisibleRows);
  }

  @override
  void dispose() {
    _routeController.dispose();
    _scrollController.removeListener(_armVisibleRows);
    _scrollController.dispose();
    _armedThroughRow.dispose();
    super.dispose();
  }

  /// Last row whose avatars are allowed to fetch: everything on screen plus
  /// one row of lookahead, so a face decodes just before it scrolls in.
  int _visibleThroughRow(ContactHexLayoutResult layout, double fallbackHeight) {
    if (layout.slots.isEmpty) return 0;
    final attached = _scrollController.hasClients;
    final offset = attached ? _scrollController.position.pixels : 0.0;
    final viewport = attached
        ? _scrollController.position.viewportDimension
        : fallbackHeight;
    final bottom = offset + viewport + layout.rowPitch;
    final rows = ((bottom - layout.slots.first.dy) / layout.rowPitch).ceil();
    return rows.clamp(0, math.max(0, layout.rowCount - 1));
  }

  void _armVisibleRows() {
    final layout = _lastLayout;
    if (layout == null) return;
    final next = _visibleThroughRow(layout, 0);
    if (next > _armedThroughRow.value) _armedThroughRow.value = next;
  }

  void _activateContact(UserModel contact, bool disableAnimations) {
    if (disableAnimations) {
      widget.onContactTap(contact);
      return;
    }
    if (_routeController.isAnimating) return;
    setState(() => _routeContactId = contact.id);
    _routeController.forward(from: 0);
  }

  /// Only a contact whose wire already exists (doubled socket = a real
  /// conversation) can be entered directly; everyone else opens the card,
  /// so a stray long press can never create a conversation.
  bool _canOpenChat(UserModel contact) =>
      widget.onContactOpenChat != null &&
      widget.conversationContactIds.contains(contact.id);

  /// Secondary activation: travel the existing wire straight into the chat.
  /// No route fill — the chat route is deliberately zero-duration, so an
  /// animation here would only add 480ms in front of it.
  void _openChat(UserModel contact) {
    final openChat = widget.onContactOpenChat;
    if (openChat == null) return;
    if (_routeController.isAnimating) return;
    if (!kIsWeb) HapticFeedback.selectionClick();
    openChat(contact);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    final nodeTextStyle = RpgTheme.bodyFont(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );
    final labelHeight = _measureHeight(
      nodeTextStyle,
      textScaler,
      textDirection,
    );

    final inputs = ContactHexLayout.sortContacts([
      for (final contact in widget.contacts)
        ContactHexLayoutInput(id: contact.id, displayName: contact.username),
    ]);
    final contactsById = <int, UserModel>{
      for (final contact in widget.contacts) contact.id: contact,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullSize = Size(constraints.maxWidth, constraints.maxHeight);
        final safeRect = _safeRect(fullSize, widget.safeInsets);
        final layout = ContactHexLayout.resolve(
          contacts: inputs,
          width: safeRect.width,
          labelHeight: labelHeight,
          leadingSlots: widget.onAddContact == null ? 0 : 1,
        );
        final viewportHeight = safeRect.height;
        final fieldHeight = math.max(layout.fieldHeight, viewportHeight);
        // Plain assignments, deliberately not setState: we are already
        // inside build, and notifying the arming notifier here would fire
        // listeners mid-build.
        _lastLayout = layout;
        _armedFloor = _visibleThroughRow(layout, viewportHeight);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: safeRect,
              child: Semantics(
                container: true,
                label: widget.networkSemanticLabel,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: layout.fieldHeight > viewportHeight
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: safeRect.width,
                      height: fieldHeight,
                      child: _buildField(
                        context,
                        layout,
                        inputs,
                        contactsById,
                        nodeTextStyle,
                        colors,
                        colorScheme,
                        disableAnimations,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: safeRect,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _NetworkFramePainter(color: colors.borderColor),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (widget.mapCaption != null && widget.contacts.isNotEmpty)
              Positioned(
                left: safeRect.left + 14,
                top: safeRect.bottom - 30,
                child: ExcludeSemantics(
                  child: Text(
                    widget.mapCaption!,
                    style: RpgTheme.bodyFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.mutedText,
                    ).copyWith(letterSpacing: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildField(
    BuildContext context,
    ContactHexLayoutResult layout,
    List<ContactHexLayoutInput> inputs,
    Map<int, UserModel> contactsById,
    TextStyle nodeTextStyle,
    FireplaceColors colors,
    ColorScheme colorScheme,
    bool disableAnimations,
  ) {
    return TweenAnimationBuilder<double>(
      duration: disableAnimations || _entranceCompleted
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      onEnd: () {
        if (_entranceCompleted) return;
        // Under reduce-motion the zero-duration tween completes during the
        // first build; setState here would be a during-build rebuild.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_entranceCompleted) {
            setState(() => _entranceCompleted = true);
          }
        });
      },
      builder: (context, entrance, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The route controller drives ONLY this painter, so only this
            // subtree may listen to it. It used to wrap the whole Stack:
            // every frame of the 480ms fill rebuilt every contact node -
            // Focus, Semantics, GestureDetector, ClipPath and Image apiece -
            // which is ~6k subtree builds for one tap on a 100-contact
            // board. The nodes only care about `_routeContactId`, which
            // changes twice per tap via setState.
            Positioned.fill(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _routeController,
                      builder: (context, _) => CustomPaint(
                        painter: _HexFieldPainter(
                          layout: layout,
                          conversationIds: widget.conversationContactIds,
                          baseColor: colorScheme.onSurface,
                          accent: colorScheme.primary,
                          entranceProgress: entrance,
                          routeProgress: _routeContactId == null
                              ? 0
                              : Curves.easeInOut.transform(
                                  _routeController.value,
                                ),
                          routeIndex: _slotIndexOf(layout, _routeContactId),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildCore(context, layout, entrance),
            if (widget.pendingRequestCount > 0)
              _buildInboundPort(context, layout, entrance),
            for (var index = 0; index < inputs.length; index++)
              _buildContactNode(
                context,
                contactsById[inputs[index].id]!,
                inputs[index],
                layout,
                index,
                nodeTextStyle,
                entrance,
                disableAnimations,
              ),
            if (layout.leadingSlots > 0)
              _buildAddNode(context, layout, nodeTextStyle, entrance),
            if (inputs.isEmpty) _buildEmptyCopy(context, layout),
          ],
        );
      },
    );
  }

  /// Slot index of a contact — the field may own leading slots the contact
  /// list does not know about.
  static int? _slotIndexOf(ContactHexLayoutResult layout, int? contactId) {
    if (contactId == null) return null;
    for (var i = 0; i < layout.inputs.length; i++) {
      if (layout.inputs[i].id == contactId) return i + layout.leadingSlots;
    }
    return null;
  }

  Widget _buildCore(
    BuildContext context,
    ContactHexLayoutResult layout,
    double entrance,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    const radius = ContactHexLayout.coreRadius;
    final captionStyle = RpgTheme.bodyFont(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurface,
    ).copyWith(letterSpacing: 1.5);

    // Full-width band, NOT a box hugging the avatar: the caption is wider
    // than the reticle, and a shrink-wrapped Positioned let the Column's
    // intrinsic width (= caption width) shove the avatar right by
    // (captionWidth - 2*radius)/2. That desynced the drawn core from
    // `layout.coreCenter`, which every feed line and route is aimed at, so
    // the leftmost first-row wires visibly stopped short of the rim.
    return Positioned(
      left: 0,
      width: layout.coreCenter.dx * 2,
      top: layout.coreCenter.dy - radius,
      child: Semantics(
        container: true,
        label: widget.localNodeSemanticLabel,
        sortKey: const OrdinalSortKey(0),
        excludeSemantics: true,
        child: Opacity(
          opacity: entrance,
          child: Column(
            children: [
              SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: CustomPaint(
                  foregroundPainter: _LocalReticlePainter(
                    outline: colorScheme.onSurface,
                    accent: colorScheme.primary,
                    focused: false,
                  ),
                  child: ClipOval(
                    child: HexAvatarSurface(
                      imageUrl: widget.localNodeAvatarUrl,
                      initials: _initials(widget.localNodeLabel),
                      surface: colors.convItemBg,
                      initialsStyle: RpgTheme.bodyFont(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.localNodeCaption,
                textAlign: TextAlign.center,
                style: captionStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inbound port: pending friend requests docking into the top of the core.
  /// Rendered only when someone is actually waiting — the count is real.
  Widget _buildInboundPort(
    BuildContext context,
    ContactHexLayoutResult layout,
    double entrance,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    final count = widget.pendingRequestCount;
    final label = count > 99 ? '99+' : '$count';

    return Positioned(
      left: layout.coreCenter.dx - 46,
      top: math.max(0, layout.coreCenter.dy - ContactHexLayout.coreRadius - 34),
      width: 92,
      child: Semantics(
        container: true,
        button: true,
        label: widget.pendingRequestsSemanticLabel ?? label,
        sortKey: const OrdinalSortKey(-1),
        excludeSemantics: true,
        child: Opacity(
          opacity: entrance,
          child: Center(
            child: GestureDetector(
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onPendingRequestsTap?.call(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.convItemBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.primary),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.south, size: 12, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: RpgTheme.bodyFont(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Stub docking into the reticle rim.
                  Container(
                    width: 1.5,
                    height: 12,
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactNode(
    BuildContext context,
    UserModel contact,
    ContactHexLayoutInput input,
    ContactHexLayoutResult layout,
    int index,
    TextStyle labelStyle,
    double entrance,
    bool disableAnimations,
  ) {
    final colors = FireplaceColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final slot = layout.slots[index + layout.leadingSlots];
    final focused = _focusedContactId == contact.id;
    final routing = _routeContactId == contact.id;
    // Row-staggered entrance: rows materialize top-down within the single
    // 280ms envelope (motion budget), never per-item unbounded.
    final rowCount = math.max(1, layout.rowCount);
    final row = layout.rowOf[index + layout.leadingSlots];
    final rowT = ((entrance * (rowCount + 1)) - row).clamp(0.0, 1.0);

    return Positioned(
      left: slot.dx - layout.pitch / 2,
      top: slot.dy - ContactHexLayout.hexRadius,
      width: layout.pitch,
      child: FocusTraversalOrder(
        order: NumericFocusOrder((index + 1).toDouble()),
        child: Focus(
          onFocusChange: (hasFocus) {
            final next = hasFocus ? contact.id : null;
            if (_focusedContactId != next) {
              setState(() => _focusedContactId = next);
            }
            if (hasFocus) _revealSlot(layout, slot);
          },
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final isActivation =
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space;
            if (!isActivation) return KeyEventResult.ignored;
            // Shift+Enter is the keyboard twin of the long press.
            if (HardwareKeyboard.instance.isShiftPressed &&
                _canOpenChat(contact)) {
              _openChat(contact);
              return KeyEventResult.handled;
            }
            _activateContact(contact, disableAnimations);
            return KeyEventResult.handled;
          },
          child: Semantics.fromProperties(
            container: true,
            excludeSemantics: true,
            properties: SemanticsProperties(
              button: true,
              label: contact.username,
              sortKey: OrdinalSortKey((index + 1).toDouble()),
              onTap: () => _activateContact(contact, disableAnimations),
              onLongPress: _canOpenChat(contact)
                  ? () => _openChat(contact)
                  : null,
              hintOverrides: _canOpenChat(contact)
                  ? SemanticsHintOverrides(
                      onLongPressHint: widget.openChatSemanticHint,
                    )
                  : null,
            ),
            child: Opacity(
              opacity: rowT,
              child: Transform.scale(
                scale: 0.94 + rowT * 0.06,
                child: GestureDetector(
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _activateContact(contact, disableAnimations),
                  onLongPress: _canOpenChat(contact)
                      ? () => _openChat(contact)
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: ContactHexLayout.hexWidth,
                        height: ContactHexLayout.hexRadius * 2,
                        child: CustomPaint(
                          foregroundPainter: _HexChromePainter(
                            outline: colorScheme.onSurface,
                            accent: colorScheme.primary,
                            focused: focused || routing,
                          ),
                          // Only rows that have been on screen are allowed
                          // to fetch. A 200-contact board otherwise pulls
                          // 200 faces on mount, most of them for hexes
                          // below the fold nobody scrolls to. The listener
                          // is HERE, around the leaf, so crossing a row
                          // while scrolling rebuilds avatars and not the
                          // Focus/Semantics/GestureDetector above them.
                          child: ClipPath(
                            clipper: const HexClipper(),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _armedThroughRow,
                              builder: (context, armed, _) => HexAvatarSurface(
                                imageUrl: row <= math.max(armed, _armedFloor)
                                    ? contact.profilePictureUrl
                                    : null,
                                initials: _initials(contact.username),
                                surface: colors.convItemBg,
                                initialsStyle: RpgTheme.bodyFont(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: ContactHexLayout.labelGap),
                      Text(
                        contact.username,
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Scrolls a keyboard-focused slot's full visual rect into the viewport.
  void _revealSlot(ContactHexLayoutResult layout, Offset slot) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final top = slot.dy - ContactHexLayout.hexRadius - 16;
    final bottom =
        slot.dy + ContactHexLayout.hexRadius + layout.labelHeight + 24;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top;
    } else if (bottom > viewBottom) {
      target = bottom - position.viewportDimension;
    }
    if (target != null) {
      position.moveTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }

  /// The leading "+" cell: an empty socket waiting for the next person.
  /// Dashed, avatar-less, and never counted as a contact. It heads the field
  /// rather than trailing it — at 27 contacts a trailing cell sat seven rows
  /// down and had to be scrolled to before anyone could be added.
  Widget _buildAddNode(
    BuildContext context,
    ContactHexLayoutResult layout,
    TextStyle labelStyle,
    double entrance,
  ) {
    final colors = FireplaceColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final slot = layout.slots.first;
    final rowCount = math.max(1, layout.rowCount);
    final rowT = (entrance * (rowCount + 1)).clamp(0.0, 1.0);
    final focused = _addSlotFocused;

    return Positioned(
      left: slot.dx - layout.pitch / 2,
      top: slot.dy - ContactHexLayout.hexRadius,
      width: layout.pitch,
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(0.5),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (_addSlotFocused != hasFocus) {
              setState(() => _addSlotFocused = hasFocus);
            }
            if (hasFocus) _revealSlot(layout, slot);
          },
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onAddContact?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            container: true,
            button: true,
            label: widget.addSlotSemanticLabel ?? widget.addSlotLabel ?? '',
            sortKey: const OrdinalSortKey(0.5),
            onTap: () => widget.onAddContact?.call(),
            excludeSemantics: true,
            child: Opacity(
              opacity: rowT,
              child: Transform.scale(
                scale: 0.94 + rowT * 0.06,
                child: GestureDetector(
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onAddContact?.call(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: ContactHexLayout.hexWidth,
                        height: ContactHexLayout.hexRadius * 2,
                        child: CustomPaint(
                          painter: _AddSlotPainter(
                            outline: colorScheme.onSurface,
                            accent: colorScheme.primary,
                            focused: focused,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add,
                              size: 22,
                              color: focused
                                  ? colorScheme.primary
                                  : colors.mutedText,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: ContactHexLayout.labelGap),
                      Text(
                        widget.addSlotLabel ?? '',
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: labelStyle.copyWith(color: colors.mutedText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCopy(BuildContext context, ContactHexLayoutResult layout) {
    final colors = FireplaceColors.of(context);
    // With an add cell on the board the copy sits under it, not on top.
    final top = layout.slots.isEmpty
        ? layout.coreCenter.dy + ContactHexLayout.coreRadius + 52
        : layout.slots.last.dy +
              ContactHexLayout.hexRadius +
              ContactHexLayout.labelGap +
              layout.labelHeight +
              24;
    return Positioned(
      left: 24,
      right: 24,
      top: top,
      child: Column(
        children: [
          Text(
            widget.emptyTitle,
            textAlign: TextAlign.center,
            style: RpgTheme.bodyFont(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.emptyMessage,
            textAlign: TextAlign.center,
            style: RpgTheme.bodyFont(fontSize: 13, color: colors.mutedText),
          ),
        ],
      ),
    );
  }

  static Rect _safeRect(Size size, EdgeInsets insets) {
    final left = insets.left;
    final top = insets.top;
    final right = math.max(left + 1, size.width - insets.right);
    final bottom = math.max(top + 1, size.height - insets.bottom);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static double _measureHeight(
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    // Ceil + 1px slack: fractional text heights clip glyph descenders at
    // accessibility text scales.
    return painter.size.height.ceilToDouble() + 1;
  }

  static String _initials(String value) => hexInitials(value);
}

/// Sorting input to the pure hex-field algorithm.
@immutable
class ContactHexLayoutInput {
  const ContactHexLayoutInput({required this.id, required this.displayName});

  final int id;
  final String displayName;
}

/// Geometry is immutable; [traces] is a memo of it, built on first read.
class ContactHexLayoutResult {
  ContactHexLayoutResult({
    required this.inputs,
    required this.slots,
    required this.rowOf,
    required this.rowCount,
    this.leadingSlots = 0,
    required this.columnsWide,
    required this.pitch,
    required this.labelHeight,
    required this.coreCenter,
    required this.fieldHeight,
  });

  /// Contacts in natural-sort order. They occupy [slots] from index
  /// [leadingSlots] onward — the field may own leading cells that are not
  /// people (the "+" add cell), so the announced node count stays honest.
  final List<ContactHexLayoutInput> inputs;

  /// Hex centers: [leadingSlots] field-owned cells, then one per contact.
  final List<Offset> slots;

  /// Row index per slot, parallel to [slots].
  final List<int> rowOf;

  final int rowCount;

  /// Slots at the head of the field that belong to the field, not to a
  /// contact. Contact `i` lives at `slots[i + leadingSlots]`.
  final int leadingSlots;

  /// Column count of a full wide row (4 on phones, up to 8 on desktop).
  final int columnsWide;
  final double pitch;
  final double labelHeight;
  final Offset coreCenter;
  final double fieldHeight;

  Path? _traces;

  /// Every contact's dormant trace as ONE path, built on first read and
  /// reused for the life of this layout.
  ///
  /// One path, one stroke, on purpose. Drawing 27 separate paths meant
  /// overlapping segments composited 27 times, so the bundle under the core
  /// darkened to near-opaque while the same stroke stayed faint lower down.
  /// A single draw unions the coverage: uniform weight everywhere. It also
  /// keeps `routePath` off the paint path — it sorts peers to fan the rim,
  /// and the 480ms tap fill repaints every frame.
  Path get traces {
    final cached = _traces;
    if (cached != null) return cached;
    final combined = Path();
    for (var i = leadingSlots; i < slots.length; i++) {
      combined.addPath(ContactHexLayout.routePath(this, i), Offset.zero);
    }
    return _traces = combined;
  }

  /// Vertical distance between row centres — the same value `resolve` laid
  /// the rows out on.
  double get rowPitch =>
      ContactHexLayout.hexRadius * 2 +
      ContactHexLayout.labelGap +
      labelHeight +
      9;

  /// Full visual rect (hex + label) of one slot, for tests and reveal math.
  Rect visualRectAt(int index) {
    final slot = slots[index];
    return Rect.fromLTWH(
      slot.dx - pitch / 2,
      slot.dy - ContactHexLayout.hexRadius,
      pitch,
      ContactHexLayout.hexRadius * 2 + ContactHexLayout.labelGap + labelHeight,
    );
  }
}

/// Pure, deterministic geometry for the honeycomb field. Same contacts +
/// width + label height always produce identical slots.
class ContactHexLayout {
  static const double hexRadius = 30; // point-to-point 60
  static const double labelGap = 5;
  static const double coreRadius = 34;
  static const double maxPitch = 92;

  /// Flat-to-flat hex width for a pointy-top hexagon.
  static double get hexWidth => hexRadius * math.sqrt(3);

  static ContactHexLayoutResult resolve({
    required List<ContactHexLayoutInput> contacts,
    required double width,
    required double labelHeight,
    // Cells at the HEAD of the field that the field owns rather than a
    // contact (the "+" add slot). Reserved here so it lands on the same
    // lattice, never faked as a contact — [inputs] and the announced node
    // count stay honest.
    int leadingSlots = 0,
  }) {
    final ordered = sortContacts(contacts);
    final halfUsable = math.max(hexWidth, width / 2 - hexWidth);
    // Adaptive width: phones run 4-3 rows; wider viewports earn more
    // columns (up to 8-7) at the ideal pitch instead of a skinny strip.
    final halfSteps = (halfUsable / maxPitch + 0.5).floor().clamp(2, 4);
    final pitch = math
        .min(maxPitch, halfUsable / (halfSteps - 0.5))
        .clamp(hexWidth + 6, maxPitch)
        .toDouble();
    final wideCapacity = halfSteps * 2;
    // 48, not 64: the safe rect already begins below the header capsule, so
    // a 64px centre left ~30px of dead air above the reticle. 48 leaves
    // ~14px under the header and lifts the whole field with it, which buys
    // roughly one more visible row before scrolling.
    final coreCenter = Offset(width / 2, 48);
    final rowPitch = hexRadius * 2 + labelGap + labelHeight + 9;

    final slots = <Offset>[];
    final rowOf = <int>[];
    // Core radius + caption band + first-row clearance.
    var y = coreCenter.dy + coreRadius + 28 + hexRadius;
    var remaining = ordered.length + leadingSlots;
    var wideRow = true;
    var rowIndex = 0;
    while (remaining > 0) {
      final capacity = wideRow ? wideCapacity : wideCapacity - 1;
      final take = math.min(remaining, capacity);
      final offsets = <double>[];
      // A full row spans symmetric lattice offsets; the partial last row
      // centers itself on the same 1-pitch grid: balanced at any count.
      final start = -(take - 1) / 2;
      for (var i = 0; i < take; i++) {
        offsets.add(start + i);
      }
      for (final f in offsets) {
        slots.add(Offset(coreCenter.dx + f * pitch, y));
        rowOf.add(rowIndex);
      }
      remaining -= take;
      y += rowPitch;
      wideRow = !wideRow;
      rowIndex++;
    }
    final fieldHeight = slots.isEmpty
        ? coreCenter.dy + coreRadius + 120
        : slots.last.dy + hexRadius + labelGap + labelHeight + 40;

    return ContactHexLayoutResult(
      inputs: ordered,
      slots: slots,
      rowOf: rowOf,
      rowCount: rowIndex,
      leadingSlots: leadingSlots,
      columnsWide: wideCapacity,
      pitch: pitch,
      labelHeight: labelHeight,
      coreCenter: coreCenter,
      fieldHeight: fieldHeight,
    );
  }

  /// Route from the core rim to slot [index]'s socket pad, weaving through
  /// the lattice gap nearest the straight path in every intermediate row.
  static Path routePath(ContactHexLayoutResult layout, int index) {
    final slot = layout.slots[index];
    final pad = Offset(slot.dx, slot.dy - hexRadius - 9);
    final core = layout.coreCenter;
    final targetRow = layout.rowOf[index];

    // First-row nodes fill along their existing feed line: rim -> bend -> pad.
    if (targetRow == 0) {
      final dir = Offset(pad.dx - core.dx, 52);
      final rim = core + dir / dir.distance * coreRadius;
      return Path()
        ..moveTo(rim.dx, rim.dy)
        ..lineTo(pad.dx, pad.dy - 16)
        ..lineTo(pad.dx, pad.dy);
    }

    // Two shared exits, one per side, angled so the route clears the
    // centered LOCAL NODE caption. Sharing them is deliberate: the traces
    // that overlap here are drawn as ONE path in ONE stroke, so the shared
    // run composites a single time and stays exactly as thin as every other
    // trace no matter how many contacts feed into it.
    //
    // Fanning each trace to its own rim angle was tried and reverted. It
    // scales the wrong way: N rays converging on a 34px circle stay
    // sub-pixel apart for ~180px out, so at 100 contacts the fan fills in
    // to a solid wedge that no alpha ramp short enough to spare row 0 can
    // hide. Overlap that composites once is strictly better than overlap
    // spread into a smudge.
    final sideSign = slot.dx >= core.dx ? 1.0 : -1.0;
    final exit = Offset(core.dx + sideSign * 52, core.dy + coreRadius + 24);
    final rimDir = exit - core;
    final rim = core + rimDir / rimDir.distance * coreRadius;
    final route = Path()
      ..moveTo(rim.dx, rim.dy)
      ..lineTo(exit.dx, exit.dy);

    var prevY = exit.dy;
    for (var row = 0; row < targetRow; row++) {
      final rowXs = <double>[];
      double rowY = prevY;
      for (var j = 0; j < layout.slots.length; j++) {
        if (layout.rowOf[j] == row) {
          rowXs.add(layout.slots[j].dx);
          rowY = layout.slots[j].dy;
        }
      }
      if (rowXs.isEmpty) continue;
      rowXs.sort();
      final t = (rowY - core.dy) / math.max(1, slot.dy - core.dy);
      final idealX = core.dx + (slot.dx - core.dx) * t;
      final gaps = <double>[
        rowXs.first - layout.pitch / 2,
        for (var g = 0; g < rowXs.length - 1; g++)
          (rowXs[g] + rowXs[g + 1]) / 2,
        rowXs.last + layout.pitch / 2,
      ];
      var gapX = gaps.first;
      var best = double.infinity;
      for (final gap in gaps) {
        final d = (gap - idealX).abs();
        if (d < best) {
          best = d;
          gapX = gap;
        }
      }
      route.lineTo(gapX, rowY);
      prevY = rowY;
    }
    route
      ..lineTo(pad.dx, prevY + (pad.dy - prevY) * 0.7)
      ..lineTo(pad.dx, pad.dy);
    return route;
  }

  /// Natural sort: same prefix -> smaller number first (ziomek3, ziomek50).
  static int compareByDisplayName(
    ContactHexLayoutInput a,
    ContactHexLayoutInput b,
  ) {
    final aMatch = RegExp(r'^(.+?)(\d+)$').firstMatch(a.displayName);
    final bMatch = RegExp(r'^(.+?)(\d+)$').firstMatch(b.displayName);
    final aPrefix = (aMatch?.group(1) ?? a.displayName).toLowerCase();
    final bPrefix = (bMatch?.group(1) ?? b.displayName).toLowerCase();
    final aNumber = aMatch == null ? 0 : int.tryParse(aMatch.group(2)!) ?? 0;
    final bNumber = bMatch == null ? 0 : int.tryParse(bMatch.group(2)!) ?? 0;
    final prefixCompare = aPrefix.compareTo(bPrefix);
    if (prefixCompare != 0) return prefixCompare;
    return aNumber.compareTo(bNumber);
  }

  static List<ContactHexLayoutInput> sortContacts(
    List<ContactHexLayoutInput> contacts,
  ) {
    final sorted = List<ContactHexLayoutInput>.of(contacts)
      ..sort(compareByDisplayName);
    return sorted;
  }
}

/// Hex terminal chrome: ONE outline plus the focus halo. Drawn in the
/// field's ink (`onSurface`), not `convItemBorder` — that token is a
/// near-invisible hairline on the light themes (#E8E3DC on #FAF8F5) and
/// left every empty cell ghosted while the wires beside it read fine.
class _HexChromePainter extends CustomPainter {
  const _HexChromePainter({
    required this.outline,
    required this.accent,
    required this.focused,
  });

  final Color outline;
  final Color accent;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.height / 2 - 0.75;
    // Single border by owner call: the old inner hairline at r-3 read as a
    // double edge drawn on top of the avatar.
    canvas.drawPath(
      hexPath(c, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = outline.withValues(alpha: 0.42),
    );
    if (focused) {
      canvas.drawPath(
        hexPath(c, r + 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HexChromePainter oldDelegate) =>
      oldDelegate.outline != outline ||
      oldDelegate.accent != accent ||
      oldDelegate.focused != focused;
}

/// Dashed hex outline for the "+" add cell: a socket with nobody in it yet.
class _AddSlotPainter extends CustomPainter {
  const _AddSlotPainter({
    required this.outline,
    required this.accent,
    required this.focused,
  });

  final Color outline;
  final Color accent;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.height / 2 - 0.75;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = focused ? accent : outline.withValues(alpha: 0.45);

    // Dash the outline by walking the hex path in 5px on / 4px off runs.
    for (final metric in hexPath(c, r).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 5, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AddSlotPainter oldDelegate) =>
      oldDelegate.outline != outline ||
      oldDelegate.accent != accent ||
      oldDelegate.focused != focused;
}

/// Instrument reticle for the local node: the accent ring rides the
/// circumference and N/E/S/W ticks sit just inside it. No inner ring —
/// a second circle drawn over the avatar read as a border on the picture
/// (owner nit).
class _LocalReticlePainter extends CustomPainter {
  const _LocalReticlePainter({
    required this.outline,
    required this.accent,
    required this.focused,
  });

  final Color outline;
  final Color accent;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final stroke = Paint()..style = PaintingStyle.stroke;

    stroke
      ..strokeWidth = 1.5
      ..color = accent;
    canvas.drawCircle(c, r - 0.75, stroke);

    stroke
      ..strokeWidth = 1
      ..color = outline.withValues(alpha: 0.45);
    for (final d in const [
      Offset(0, -1),
      Offset(1, 0),
      Offset(0, 1),
      Offset(-1, 0),
    ]) {
      canvas.drawLine(c + d * (r - 5.5), c + d * (r - 1.5), stroke);
    }

    if (focused) {
      stroke
        ..strokeWidth = 1
        ..color = accent;
      canvas.drawCircle(c, r + 3, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LocalReticlePainter oldDelegate) =>
      oldDelegate.outline != outline ||
      oldDelegate.accent != accent ||
      oldDelegate.focused != focused;
}

/// Screen-fixed corner brackets framing the field viewport.
class _NetworkFramePainter extends CustomPainter {
  const _NetworkFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    const arm = 14.0;
    final p = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.35);
    for (final c in <(Offset, Offset, Offset)>[
      (Offset(inset, inset), const Offset(1, 0), const Offset(0, 1)),
      (
        Offset(size.width - inset, inset),
        const Offset(-1, 0),
        const Offset(0, 1),
      ),
      (
        Offset(inset, size.height - inset),
        const Offset(1, 0),
        const Offset(0, -1),
      ),
      (
        Offset(size.width - inset, size.height - inset),
        const Offset(-1, 0),
        const Offset(0, -1),
      ),
    ]) {
      canvas.drawLine(c.$1, c.$1 + c.$2 * arm, p);
      canvas.drawLine(c.$1, c.$1 + c.$3 * arm, p);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The field's ambient and wiring layer: faint unoccupied lattice points,
/// per-node socket stubs (doubled = conversation), the core's visible feed
/// to the first row, and the tap/focus route fill.
class _HexFieldPainter extends CustomPainter {
  const _HexFieldPainter({
    required this.layout,
    required this.conversationIds,
    required this.baseColor,
    required this.accent,
    required this.entranceProgress,
    required this.routeProgress,
    required this.routeIndex,
  });

  final ContactHexLayoutResult layout;
  final Set<int> conversationIds;
  final Color baseColor;
  final Color accent;
  final double entranceProgress;
  final double routeProgress;
  final int? routeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final core = layout.coreCenter;

    // Faint lattice points continuing past the populated rows: the machine
    // frame has free sockets (chrome, not fake contacts).
    final dotPaint = Paint()..color = baseColor.withValues(alpha: 0.16);
    if (layout.slots.isNotEmpty) {
      final rowPitch = layout.rowPitch;
      var wideRow = layout.rowCount.isEven;
      for (
        var y = layout.slots.last.dy + rowPitch;
        y < size.height - 24;
        y += rowPitch
      ) {
        final count = wideRow ? layout.columnsWide : layout.columnsWide - 1;
        final offsets = [for (var i = 0; i < count; i++) -(count - 1) / 2 + i];
        for (final f in offsets) {
          canvas.drawCircle(
            Offset(core.dx + f * layout.pitch, y),
            1.2,
            dotPaint,
          );
        }
        wideRow = !wideRow;
      }
    }

    // Per-node sockets; the pads brighten with the entrance sweep row by row.
    final stubPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    final padPaint = Paint();
    final rowCount = math.max(1, layout.rowCount);
    for (var i = 0; i < layout.slots.length; i++) {
      final slot = layout.slots[i];
      final row = layout.rowOf[i];
      final rowT = ((entranceProgress * (rowCount + 1)) - row).clamp(0.0, 1.0);
      if (rowT <= 0) continue;
      // The leading add cell has no contact behind it: single, empty socket.
      final contactIndex = i - layout.leadingSlots;
      final hasConv =
          contactIndex >= 0 &&
          conversationIds.contains(layout.inputs[contactIndex].id);
      stubPaint.color = baseColor.withValues(alpha: 0.38 * rowT);
      padPaint.color = baseColor.withValues(alpha: 0.60 * rowT);
      final top = Offset(slot.dx, slot.dy - ContactHexLayout.hexRadius);
      void stub(double dx) {
        final base = Offset(top.dx + dx, top.dy - 1);
        final tip = Offset(top.dx + dx, top.dy - 9);
        canvas.drawLine(base, tip, stubPaint);
        canvas.drawRect(
          Rect.fromCenter(center: tip, width: 3, height: 3),
          padPaint,
        );
      }

      if (hasConv) {
        stub(-2.2);
        stub(2.2);
      } else {
        stub(0);
      }
    }

    // Every relationship is drawn, dormant, all the time: the board is a
    // wired board, not four wired nodes and the rest floating. One trace per
    // real contact - no bus, no shared rail - so the picture still cannot
    // lie about who you know. Tapping does not conjure a wire, it energises
    // the one already there.
    //
    // ONE path, ONE stroke. That is what keeps it thin: shared runs near the
    // core overlap heavily, and drawing each trace separately composited
    // them 13-deep into a fat bundle while the same stroke stayed faint
    // further down. A single draw unions the coverage, so the picture has
    // uniform weight at 3 contacts and at 300.
    if (entranceProgress > 0) {
      canvas.drawPath(
        layout.traces,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = baseColor.withValues(alpha: 0.17 * entranceProgress),
      );
    }

    // Tap/focus route: the connection fills with the accent color from the
    // contact's socket up to the local core.
    final index = routeIndex;
    if (index != null && index < layout.slots.length && routeProgress > 0) {
      final route = ContactHexLayout.routePath(layout, index);
      final metrics = route.computeMetrics().toList(growable: false);
      if (metrics.isNotEmpty) {
        var total = 0.0;
        for (final m in metrics) {
          total += m.length;
        }
        // The visible strip grows from the node's pad toward the core: the
        // path runs core->pad, so we reveal its tail first.
        var remainingStart = total * (1 - routeProgress);
        final routePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.square
          ..color = accent.withValues(alpha: 0.9);
        for (final m in metrics) {
          if (remainingStart >= m.length) {
            remainingStart -= m.length;
            continue;
          }
          canvas.drawPath(m.extractPath(remainingStart, m.length), routePaint);
          remainingStart = 0;
        }
        // Bright head where the strip currently is: makes the travel
        // direction (node -> core) readable at a glance.
        if (routeProgress < 1) {
          var headOffset = total * (1 - routeProgress);
          for (final m in metrics) {
            if (headOffset > m.length) {
              headOffset -= m.length;
              continue;
            }
            final head = m.getTangentForOffset(headOffset)?.position;
            if (head != null) {
              canvas.drawCircle(head, 2.6, Paint()..color = accent);
            }
            break;
          }
        }
        final slot = layout.slots[index];
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(slot.dx, slot.dy - ContactHexLayout.hexRadius - 9),
            width: 3.5,
            height: 3.5,
          ),
          Paint()..color = accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HexFieldPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.accent != accent ||
      oldDelegate.entranceProgress != entranceProgress ||
      oldDelegate.routeProgress != routeProgress ||
      oldDelegate.routeIndex != routeIndex;
}
