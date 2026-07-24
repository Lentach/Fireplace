import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../config/app_config.dart';
import '../models/user_model.dart';
import '../theme/rpg_theme.dart';

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
          )
          ..addStatusListener((status) {
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
  }

  @override
  void dispose() {
    _routeController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final labelHeight = _measureHeight(nodeTextStyle, textScaler, textDirection);

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
        );
        final viewportHeight = safeRect.height;
        final fieldHeight = math.max(layout.fieldHeight, viewportHeight);

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
        return AnimatedBuilder(
          animation: _routeController,
          builder: (context, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _HexFieldPainter(
                            layout: layout,
                            conversationIds: widget.conversationContactIds,
                            baseColor: colorScheme.onSurface,
                            borderColor: colors.convItemBorder,
                            accent: colorScheme.primary,
                            entranceProgress: entrance,
                            routeProgress: _routeContactId == null
                                ? 0
                                : Curves.easeInOut.transform(
                                    _routeController.value,
                                  ),
                            routeIndex: _slotIndexOf(
                              layout,
                              _routeContactId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildCore(context, layout, entrance),
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
                if (inputs.isEmpty) _buildEmptyCopy(context, layout),
              ],
            );
          },
        );
      },
    );
  }

  static int? _slotIndexOf(ContactHexLayoutResult layout, int? contactId) {
    if (contactId == null) return null;
    for (var i = 0; i < layout.inputs.length; i++) {
      if (layout.inputs[i].id == contactId) return i;
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

    return Positioned(
      left: layout.coreCenter.dx - radius,
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
                    borderColor: colors.convItemBorder,
                    accent: colorScheme.primary,
                    focused: false,
                  ),
                  child: ClipOval(
                    child: _HexAvatar(
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
              Text(widget.localNodeCaption, style: captionStyle),
            ],
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
    final slot = layout.slots[index];
    final focused = _focusedContactId == contact.id;
    final routing = _routeContactId == contact.id;
    // Row-staggered entrance: rows materialize top-down within the single
    // 280ms envelope (motion budget), never per-item unbounded.
    final rowCount = math.max(1, layout.rowCount);
    final row = layout.rowOf[index];
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
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              _activateContact(contact, disableAnimations);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            container: true,
            button: true,
            label: contact.username,
            sortKey: OrdinalSortKey((index + 1).toDouble()),
            onTap: () => _activateContact(contact, disableAnimations),
            excludeSemantics: true,
            child: Opacity(
              opacity: rowT,
              child: Transform.scale(
                scale: 0.94 + rowT * 0.06,
                child: GestureDetector(
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _activateContact(contact, disableAnimations),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: ContactHexLayout.hexWidth,
                        height: ContactHexLayout.hexRadius * 2,
                        child: CustomPaint(
                          foregroundPainter: _HexChromePainter(
                            borderColor: colors.convItemBorder,
                            accent: colorScheme.primary,
                            focused: focused || routing,
                          ),
                          child: ClipPath(
                            clipper: const _HexClipper(),
                            child: _HexAvatar(
                              imageUrl: contact.profilePictureUrl,
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
    final bottom = slot.dy + ContactHexLayout.hexRadius + layout.labelHeight + 24;
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

  Widget _buildEmptyCopy(
    BuildContext context,
    ContactHexLayoutResult layout,
  ) {
    final colors = FireplaceColors.of(context);
    return Positioned(
      left: 24,
      right: 24,
      top: layout.coreCenter.dy + ContactHexLayout.coreRadius + 52,
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

  static String _initials(String value) {
    final parts = value
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final initials = parts
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();
    return initials.isEmpty ? '?' : initials;
  }
}

/// Sorting input to the pure hex-field algorithm.
@immutable
class ContactHexLayoutInput {
  const ContactHexLayoutInput({required this.id, required this.displayName});

  final int id;
  final String displayName;
}

@immutable
class ContactHexLayoutResult {
  const ContactHexLayoutResult({
    required this.inputs,
    required this.slots,
    required this.rowOf,
    required this.rowCount,
    required this.columnsWide,
    required this.pitch,
    required this.labelHeight,
    required this.coreCenter,
    required this.fieldHeight,
  });

  /// Contacts in slot order (natural sort by display name).
  final List<ContactHexLayoutInput> inputs;

  /// Hex centers, parallel to [inputs].
  final List<Offset> slots;

  /// Row index per slot, parallel to [inputs].
  final List<int> rowOf;

  final int rowCount;

  /// Column count of a full wide row (4 on phones, up to 8 on desktop).
  final int columnsWide;
  final double pitch;
  final double labelHeight;
  final Offset coreCenter;
  final double fieldHeight;

  /// Full visual rect (hex + label) of one slot, for tests and reveal math.
  Rect visualRectAt(int index) {
    final slot = slots[index];
    return Rect.fromLTWH(
      slot.dx - pitch / 2,
      slot.dy - ContactHexLayout.hexRadius,
      pitch,
      ContactHexLayout.hexRadius * 2 +
          ContactHexLayout.labelGap +
          labelHeight,
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
    final coreCenter = Offset(width / 2, 64);
    final rowPitch = hexRadius * 2 + labelGap + labelHeight + 9;

    final slots = <Offset>[];
    final rowOf = <int>[];
    // Core radius + caption band + first-row clearance.
    var y = coreCenter.dy + coreRadius + 28 + hexRadius;
    var remaining = ordered.length;
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

    // Exit the rim angled toward the target side so the route clears the
    // centered LOCAL NODE caption below the core.
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

/// Pointy-top hexagon path centered on [c].
Path _hexPath(Offset c, double r) {
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final a = -math.pi / 2 + i * math.pi / 3;
    final p = c + Offset(math.cos(a), math.sin(a)) * r;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// Hex terminal chrome: outline, inner hairline, focus halo. Painted over
/// the clipped avatar/initials surface so edges stay crisp.
class _HexChromePainter extends CustomPainter {
  const _HexChromePainter({
    required this.borderColor,
    required this.accent,
    required this.focused,
  });

  final Color borderColor;
  final Color accent;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.height / 2 - 0.75;
    canvas.drawPath(
      _hexPath(c, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = borderColor.withValues(alpha: 0.6),
    );
    canvas.drawPath(
      _hexPath(c, r - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor.withValues(alpha: 0.22),
    );
    if (focused) {
      canvas.drawPath(
        _hexPath(c, r + 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HexChromePainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.accent != accent ||
      oldDelegate.focused != focused;
}

class _HexClipper extends CustomClipper<Path> {
  const _HexClipper();

  @override
  Path getClip(Size size) => _hexPath(
    Offset(size.width / 2, size.height / 2),
    size.height / 2 - 0.75,
  );

  @override
  bool shouldReclip(covariant _HexClipper oldClipper) => false;
}

/// The hex surface: the contact's avatar covering the whole hex, or the
/// themed surface + initials when there is no (loadable) avatar.
class _HexAvatar extends StatefulWidget {
  const _HexAvatar({
    required this.imageUrl,
    required this.initials,
    required this.surface,
    required this.initialsStyle,
  });

  final String? imageUrl;
  final String initials;
  final Color surface;
  final TextStyle initialsStyle;

  @override
  State<_HexAvatar> createState() => _HexAvatarState();
}

class _HexAvatarState extends State<_HexAvatar> {
  bool _imageLoadError = false;

  @override
  void didUpdateWidget(_HexAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageLoadError = false;
    }
  }

  String _resolvedUrl() {
    final url = widget.imageUrl!;
    final isAbsolute =
        url.startsWith('http://') || url.startsWith('https://');
    // Same resolution as AvatarCircle: the per-upload UUID filename is the
    // cache key, no cache-busting query.
    return isAbsolute ? url : '${AppConfig.baseUrl}$url';
  }

  Widget _fallback() {
    return ColoredBox(
      color: widget.surface,
      child: Center(
        child: Text(widget.initials, style: widget.initialsStyle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    if (url == null || url.trim().isEmpty || _imageLoadError) {
      return _fallback();
    }
    return Image.network(
      _resolvedUrl(),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _imageLoadError = true);
        });
        return _fallback();
      },
      loadingBuilder: (context, child, loadingProgress) =>
          loadingProgress == null ? child : _fallback(),
    );
  }
}

/// Instrument reticle for the local node: outer ring, N/E/S/W ticks in the
/// gap band, and an inner accent ring around the surface disc.
class _LocalReticlePainter extends CustomPainter {
  const _LocalReticlePainter({
    required this.borderColor,
    required this.accent,
    required this.focused,
  });

  final Color borderColor;
  final Color accent;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final stroke = Paint()..style = PaintingStyle.stroke;

    // Accent ring rides the circumference (owner nit: it used to cut 6px
    // into the avatar); the plain hairline sits inside as the inner ring.
    stroke
      ..strokeWidth = 1
      ..color = borderColor;
    canvas.drawCircle(c, r - 6, stroke);

    stroke
      ..strokeWidth = 1.5
      ..color = accent;
    canvas.drawCircle(c, r - 0.75, stroke);

    stroke
      ..strokeWidth = 1
      ..color = borderColor.withValues(alpha: 0.6);
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
      oldDelegate.borderColor != borderColor ||
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
    required this.borderColor,
    required this.accent,
    required this.entranceProgress,
    required this.routeProgress,
    required this.routeIndex,
  });

  final ContactHexLayoutResult layout;
  final Set<int> conversationIds;
  final Color baseColor;
  final Color borderColor;
  final Color accent;
  final double entranceProgress;
  final double routeProgress;
  final int? routeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final core = layout.coreCenter;

    // Faint lattice points continuing past the populated rows: the machine
    // frame has free sockets (chrome, not fake contacts).
    final dotPaint = Paint()..color = borderColor.withValues(alpha: 0.18);
    if (layout.slots.isNotEmpty) {
      final rowPitch = ContactHexLayout.hexRadius * 2 +
          ContactHexLayout.labelGap +
          layout.labelHeight +
          9;
      var wideRow = layout.rowCount.isEven;
      for (var y = layout.slots.last.dy + rowPitch;
          y < size.height - 24;
          y += rowPitch) {
        final count = wideRow ? layout.columnsWide : layout.columnsWide - 1;
        final offsets = [
          for (var i = 0; i < count; i++) -(count - 1) / 2 + i,
        ];
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
      final rowT =
          ((entranceProgress * (rowCount + 1)) - row).clamp(0.0, 1.0);
      if (rowT <= 0) continue;
      final hasConv = conversationIds.contains(layout.inputs[i].id);
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

      // The core visibly feeds the first row.
      if (row == 0) {
        final pad = Offset(top.dx, top.dy - 9);
        final dir = Offset(pad.dx - core.dx, 52);
        final rim = core + dir / dir.distance * ContactHexLayout.coreRadius;
        stubPaint.color = baseColor.withValues(alpha: 0.30 * rowT);
        final path = Path()
          ..moveTo(rim.dx, rim.dy)
          ..lineTo(pad.dx, pad.dy - 16)
          ..lineTo(pad.dx, pad.dy - 1.5);
        canvas.drawPath(path, stubPaint);
      }
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
          canvas.drawPath(
            m.extractPath(remainingStart, m.length),
            routePaint,
          );
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
            center: Offset(
              slot.dx,
              slot.dy - ContactHexLayout.hexRadius - 9,
            ),
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
      oldDelegate.borderColor != borderColor ||
      oldDelegate.accent != accent ||
      oldDelegate.entranceProgress != entranceProgress ||
      oldDelegate.routeProgress != routeProgress ||
      oldDelegate.routeIndex != routeIndex;
}

