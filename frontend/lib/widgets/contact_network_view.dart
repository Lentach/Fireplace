import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../theme/rpg_theme.dart';

/// A provider-free rendering of the existing contact set as an opaque-node map.
///
/// The parent owns contact data and navigation. Saved pin coordinates are only
/// hints: each build resolves them through live viewport and label geometry.
class ContactNetworkView extends StatefulWidget {
  const ContactNetworkView({
    super.key,
    required this.contacts,
    required this.localNodeLabel,
    required this.localNodeCaption,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onContactTap,
    required this.networkSemanticLabel,
    required this.localNodeSemanticLabel,
    this.safeInsets = EdgeInsets.zero,
    this.storageUserId,
    this.resetLayoutLabel,
    this.dragHint,
    this.conversationContactIds = const <int>{},
    this.mapCaption,
    this.onLayoutReset,
  });

  final List<UserModel> contacts;
  final String localNodeLabel;
  final String localNodeCaption;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<UserModel> onContactTap;
  final String networkSemanticLabel;
  final String localNodeSemanticLabel;

  /// Parent chrome clearance, such as the floating tab header and navigation.
  final EdgeInsets safeInsets;

  /// Enables the per-user SharedPreferences layout hint store when non-null.
  final int? storageUserId;
  final String? resetLayoutLabel;
  final String? dragHint;

  /// Ids of contacts that already share a conversation with the local user.
  /// Their trace renders doubled. Purely visual; the parent supplies real data.
  final Set<int> conversationContactIds;

  /// Factual micro-caption under the bottom-left frame bracket (node count).
  final String? mapCaption;
  final VoidCallback? onLayoutReset;

  @override
  State<ContactNetworkView> createState() => _ContactNetworkViewState();
}

class _ContactNetworkViewState extends State<ContactNetworkView> {
  final _boardKey = GlobalKey();
  final _viewerController = TransformationController();
  final Map<int, Offset> _savedPins = <int, Offset>{};
  final Map<int, Offset> _dragPins = <int, Offset>{};

  ContactNetworkLayoutStore? _layoutStore;
  int? _loadedStorageUserId;
  int? _draggingContactId;
  int? _pulsingContactId;
  int? _focusedContactId;
  String? _viewerSignature;
  Size? _viewerViewport;
  bool _entranceCompleted = false;

  @override
  void initState() {
    super.initState();
    _startStorageFor(widget.storageUserId);
  }

  @override
  void didUpdateWidget(covariant ContactNetworkView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageUserId != widget.storageUserId) {
      _savedPins.clear();
      _dragPins.clear();
      _viewerSignature = null;
      _startStorageFor(widget.storageUserId);
    }
  }

  @override
  void dispose() {
    _viewerController.dispose();
    super.dispose();
  }

  void _startStorageFor(int? userId) {
    _loadedStorageUserId = userId;
    _layoutStore = userId == null ? null : ContactNetworkLayoutStore(userId);
    if (_layoutStore != null) {
      _loadSavedPins().ignore();
    }
  }

  Future<void> _loadSavedPins() async {
    final store = _layoutStore;
    final expectedUserId = _loadedStorageUserId;
    if (store == null || expectedUserId == null) return;

    final loaded = await store.load();
    if (!mounted || _loadedStorageUserId != expectedUserId) return;
    setState(() {
      _savedPins
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> _resetLayout() async {
    setState(() {
      _savedPins.clear();
      _dragPins.clear();
    });
    await _layoutStore?.clear();
    widget.onLayoutReset?.call();
  }

  void _handleTap(UserModel contact, bool disableAnimations) {
    if (disableAnimations) {
      widget.onContactTap(contact);
      return;
    }

    setState(() => _pulsingContactId = contact.id);
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _pulsingContactId != contact.id) return;
      setState(() => _pulsingContactId = null);
      widget.onContactTap(contact);
    }).ignore();
  }

  void _startDrag(UserModel contact) {
    setState(() => _draggingContactId = contact.id);
  }

  void _updateDrag(
    UserModel contact,
    LongPressMoveUpdateDetails details,
    ContactNetworkLayoutResult layout,
  ) {
    final boardContext = _boardKey.currentContext;
    if (boardContext == null) return;
    final renderBox = boardContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final candidate = renderBox.globalToLocal(details.globalPosition);
    setState(() {
      _dragPins[contact.id] = ContactNetworkLayout.clampCenter(
        candidate,
        layout.metrics,
        layout.inputById[contact.id]!,
      );
    });
  }

  Future<void> _finishDrag(
    UserModel contact,
    ContactNetworkLayoutResult layout,
  ) async {
    final center = _dragPins[contact.id];
    setState(() => _draggingContactId = null);
    if (center == null) return;

    _savedPins[contact.id] = ContactNetworkLayout.toNormalized(
      center,
      layout.metrics,
      layout.inputById[contact.id]!,
    );
    await _layoutStore?.save(_savedPins);
  }

  void _centerInteractiveMap(ContactNetworkLayoutResult layout, Size viewport) {
    _viewerViewport = viewport;
    if (!layout.usesInteractiveViewer) {
      _viewerSignature = null;
      return;
    }

    final signature = '${layout.mapSize}|${layout.localCenter}';
    if (_viewerSignature == signature) return;
    _viewerSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !layout.usesInteractiveViewer) return;
      _viewerController.value = Matrix4.identity()
        ..translateByDouble(
          viewport.width / 2 - layout.localCenter.dx,
          viewport.height / 2 - layout.localCenter.dy,
          0,
          1,
        );
    });
  }

  /// Pans the interactive map so a keyboard-focused node's full visual rect
  /// (node + label) is inside the viewport; [InteractiveViewer] never reveals
  /// focus by itself.
  void _revealFocusedNode(
    ContactNetworkLayoutResult layout,
    ContactNetworkLayoutInput input,
    Offset center,
  ) {
    final viewport = _viewerViewport;
    if (!layout.usesInteractiveViewer || viewport == null) return;

    final rect = layout.metrics.visualRectFor(input, center).inflate(16);
    final current = _viewerController.value;
    final scale = current.getMaxScaleOnAxis();
    final tx = current.storage[12];
    final ty = current.storage[13];
    final visibleLeft = -tx / scale;
    final visibleTop = -ty / scale;
    final visibleRight = visibleLeft + viewport.width / scale;
    final visibleBottom = visibleTop + viewport.height / scale;

    var newTx = tx;
    var newTy = ty;
    if (rect.left < visibleLeft) {
      newTx = -rect.left * scale;
    } else if (rect.right > visibleRight) {
      newTx = -(rect.right - viewport.width / scale) * scale;
    }
    if (rect.top < visibleTop) {
      newTy = -rect.top * scale;
    } else if (rect.bottom > visibleBottom) {
      newTy = -(rect.bottom - viewport.height / scale) * scale;
    }
    if (newTx != tx || newTy != ty) {
      _viewerController.value = current.clone()
        ..setTranslationRaw(newTx, newTy, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final nodeTextStyle = RpgTheme.bodyFont(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final localTextStyle = RpgTheme.bodyFont(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final inputs = ContactNetworkLayout.sortContacts([
      for (final contact in widget.contacts)
        ContactNetworkLayoutInput(
          id: contact.id,
          displayName: contact.username,
          labelSize: _measureLabel(
            contact.username,
            nodeTextStyle,
            textScaler,
            textDirection,
          ),
        ),
    ]);
    final localLabelSize = _measureLabel(
      widget.localNodeCaption,
      localTextStyle,
      textScaler,
      textDirection,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullSize = Size(constraints.maxWidth, constraints.maxHeight);
        final safeRect = _safeRect(fullSize, widget.safeInsets);
        final pins = <int, Offset>{..._savedPins, ..._dragPins};
        final layout = ContactNetworkLayout.resolve(
          contacts: inputs,
          safeViewport: safeRect.size,
          localLabelSize: localLabelSize,
          savedPins: pins,
        );
        _centerInteractiveMap(layout, safeRect.size);

        final map = _buildMap(
          context,
          layout,
          inputs,
          nodeTextStyle,
          localTextStyle,
          disableAnimations,
        );
        final mappedContent = layout.usesInteractiveViewer
            ? InteractiveViewer(
                transformationController: _viewerController,
                constrained: false,
                minScale: 1,
                maxScale: 2.5,
                boundaryMargin: EdgeInsets.zero,
                child: map,
              )
            : map;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(rect: safeRect, child: mappedContent),
            if (widget.storageUserId != null &&
                widget.resetLayoutLabel != null &&
                widget.contacts.isNotEmpty)
              Positioned(
                top: safeRect.top + 2,
                right: fullSize.width - safeRect.right + 8,
                child: Semantics(
                  button: true,
                  label: widget.resetLayoutLabel,
                  child: TextButton.icon(
                    onPressed: _resetLayout,
                    icon: const Icon(Icons.restart_alt, size: 14),
                    label: Text(
                      widget.resetLayoutLabel!,
                      style: RpgTheme.bodyFont(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: safeRect,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _NetworkFramePainter(
                      color: FireplaceColors.of(context).borderColor,
                    ),
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
                      color: FireplaceColors.of(context).mutedText,
                    ).copyWith(letterSpacing: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMap(
    BuildContext context,
    ContactNetworkLayoutResult layout,
    List<ContactNetworkLayoutInput> inputs,
    TextStyle nodeTextStyle,
    TextStyle localTextStyle,
    bool disableAnimations,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final contactsById = <int, UserModel>{
      for (final contact in widget.contacts) contact.id: contact,
    };

    return TweenAnimationBuilder<double>(
      duration: disableAnimations || _entranceCompleted
          ? Duration.zero
          : const Duration(milliseconds: 240),
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
        return SizedBox(
          key: _boardKey,
          width: layout.mapSize.width,
          height: layout.mapSize.height,
          child: Semantics(
            container: true,
            label: widget.networkSemanticLabel,
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _ContactNetworkBackgroundPainter(
                              localCenter: layout.localCenter,
                              contactCenters: layout.contactCenters,
                              squareHalf: layout.metrics.nodeRadius,
                              localRadius: layout.metrics.localNodeRadius,
                              ringExtents: layout.ringExtents,
                              baseColor: colorScheme.onSurface,
                              accent: colorScheme.primary,
                              conversationIds: widget.conversationContactIds,
                              pulseProgress: entrance,
                              focusedId: _focusedContactId ?? _pulsingContactId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildLocalNode(context, layout, localTextStyle, entrance),
                  for (var index = 0; index < inputs.length; index++)
                    _buildContactNode(
                      context,
                      contactsById[inputs[index].id]!,
                      inputs[index],
                      layout,
                      nodeTextStyle,
                      entrance,
                      disableAnimations,
                      index,
                    ),
                  if (inputs.isEmpty) _buildEmptyCopy(context, layout),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalNode(
    BuildContext context,
    ContactNetworkLayoutResult layout,
    TextStyle labelStyle,
    double entrance,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    final width = layout.metrics.localVisualWidth;
    final center = layout.localCenter;
    return Positioned(
      left: center.dx - width / 2,
      top: center.dy - layout.metrics.localNodeRadius,
      child: Semantics(
        container: true,
        label: widget.localNodeSemanticLabel,
        sortKey: const OrdinalSortKey(0),
        excludeSemantics: true,
        child: Opacity(
          opacity: entrance,
          child: Transform.scale(
            scale: 0.95 + entrance * 0.05,
            child: _NetworkNode(
              centerLabel: _initials(widget.localNodeLabel),
              caption: widget.localNodeCaption,
              seed: _stableHash(widget.localNodeLabel),
              isLocal: true,
              nodeDiameter: ContactNetworkLayoutMetrics.localNodeDiameter,
              labelWidth: width,
              labelStyle: labelStyle,
              surfaceColor: colors.convItemBg,
              borderColor: colors.convItemBorder,
              foregroundColor: colorScheme.onSurface,
              accentColor: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactNode(
    BuildContext context,
    UserModel contact,
    ContactNetworkLayoutInput input,
    ContactNetworkLayoutResult layout,
    TextStyle labelStyle,
    double entrance,
    bool disableAnimations,
    int sortOrder,
  ) {
    final colors = FireplaceColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final center = layout.contactCenters[contact.id]!;
    final pulsing = _pulsingContactId == contact.id;
    final dragging = _draggingContactId == contact.id;
    final width = layout.metrics.visualWidthFor(input);
    final focused = _focusedContactId == contact.id;

    return Positioned(
      left: center.dx - width / 2,
      top: center.dy - layout.metrics.nodeRadius,
      child: FocusTraversalOrder(
        order: NumericFocusOrder((sortOrder + 1).toDouble()),
        child: Focus(
          onFocusChange: (hasFocus) {
            final next = hasFocus ? contact.id : null;
            if (_focusedContactId != next) {
              setState(() => _focusedContactId = next);
            }
            if (hasFocus) {
              _revealFocusedNode(layout, input, center);
            }
          },
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              _handleTap(contact, disableAnimations);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            container: true,
            button: true,
            label: contact.username,
            hint: widget.dragHint,
            sortKey: OrdinalSortKey((sortOrder + 1).toDouble()),
            onTap: () => _handleTap(contact, disableAnimations),
            excludeSemantics: true,
            child: Opacity(
              opacity: entrance,
              child: Transform.scale(
                scale: pulsing ? 1.08 : 0.95 + entrance * 0.05,
                child: GestureDetector(
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTap: dragging
                      ? null
                      : () => _handleTap(contact, disableAnimations),
                  onLongPressStart: (_) => _startDrag(contact),
                  onLongPressMoveUpdate: (details) =>
                      _updateDrag(contact, details, layout),
                  onLongPressEnd: (_) => _finishDrag(contact, layout).ignore(),
                  onLongPressCancel: () {
                    setState(() => _draggingContactId = null);
                  },
                  child: _NetworkNode(
                    centerLabel: _initials(contact.username),
                    caption: contact.username,
                    seed: _stableHash('node-${contact.id}'),
                    isLocal: false,
                    nodeDiameter: layout.metrics.nodeDiameter,
                    labelWidth: width,
                    labelStyle: labelStyle,
                    surfaceColor: colors.convItemBg,
                    borderColor: colors.convItemBorder,
                    foregroundColor: colorScheme.onSurface,
                    accentColor: colorScheme.primary,
                    isFocused: focused || pulsing,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCopy(
    BuildContext context,
    ContactNetworkLayoutResult layout,
  ) {
    final colors = FireplaceColors.of(context);
    final center = layout.localCenter;
    return Positioned(
      left: 24,
      right: 24,
      top: center.dy + layout.metrics.localNodeRadius + 34,
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

  static Size _measureLabel(
    String value,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    // Ceil + 1px slack: fractional text widths in a tight SizedBox clip the
    // last glyph at accessibility text scales.
    return Size(
      painter.size.width.ceilToDouble() + 1,
      painter.size.height.ceilToDouble(),
    );
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

/// One per-user JSON preference. Its values are normalized map coordinates.
class ContactNetworkLayoutStore {
  ContactNetworkLayoutStore(this.userId);

  final int userId;

  String get _key => 'contact_network_layout_v1_$userId';

  Future<Map<int, Offset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return <int, Offset>{};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final pins = <int, Offset>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key);
        final value = entry.value;
        if (id == null || value is! Map<String, dynamic>) continue;
        final x = value['x'];
        final y = value['y'];
        if (x is! num || y is! num) continue;
        final pin = Offset(x.toDouble(), y.toDouble());
        if (pin.dx >= 0 && pin.dx <= 1 && pin.dy >= 0 && pin.dy <= 1) {
          pins[id] = pin;
        }
      }
      return pins;
    } on FormatException {
      return <int, Offset>{};
    }
  }

  Future<void> save(Map<int, Offset> pins) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, Map<String, double>>{
      for (final entry in pins.entries)
        entry.key.toString(): <String, double>{
          'x': entry.value.dx.clamp(0, 1).toDouble(),
          'y': entry.value.dy.clamp(0, 1).toDouble(),
        },
    };
    await prefs.setString(_key, jsonEncode(encoded));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Measured input to the pure map algorithm. The view measures labels with the
/// live [TextScaler] before constructing these values.
@immutable
class ContactNetworkLayoutInput {
  const ContactNetworkLayoutInput({
    required this.id,
    required this.displayName,
    required this.labelSize,
  });

  final int id;
  final String displayName;
  final Size labelSize;
}

@immutable
class ContactNetworkLayoutMetrics {
  const ContactNetworkLayoutMetrics({
    required this.mapSize,
    required this.nodeDiameter,
    required this.localLabelSize,
    required this.maxContactLabelSize,
  });

  final Size mapSize;
  final double nodeDiameter;
  final Size localLabelSize;
  final Size maxContactLabelSize;

  static const double localNodeDiameter = 68;
  static const double labelGap = 5;
  static const double nodeFloorDiameter = 48;
  static const double idealNodeDiameter = 60;

  double get nodeRadius => nodeDiameter / 2;
  double get localNodeRadius => localNodeDiameter / 2;
  double get localVisualWidth =>
      math.max(localNodeDiameter, localLabelSize.width);
  double get maxVisualWidth =>
      math.max(nodeDiameter, maxContactLabelSize.width);
  double get maxVisualHeight =>
      nodeDiameter + labelGap + maxContactLabelSize.height;

  double visualWidthFor(ContactNetworkLayoutInput input) =>
      math.max(nodeDiameter, input.labelSize.width);

  double visualHeightFor(ContactNetworkLayoutInput input) =>
      nodeDiameter + labelGap + input.labelSize.height;

  Rect centerBoundsFor(ContactNetworkLayoutInput input) {
    final halfWidth = visualWidthFor(input) / 2;
    final left = halfWidth;
    final top = nodeRadius;
    final right = math.max(left, mapSize.width - halfWidth);
    final bottom = math.max(
      top,
      mapSize.height - nodeRadius - labelGap - input.labelSize.height,
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect get localCenterBounds {
    final halfWidth = localVisualWidth / 2;
    final left = halfWidth;
    final top = localNodeRadius;
    final right = math.max(left, mapSize.width - halfWidth);
    final bottom = math.max(
      top,
      mapSize.height - localNodeRadius - labelGap - localLabelSize.height,
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect visualRectFor(ContactNetworkLayoutInput input, Offset center) =>
      Rect.fromLTWH(
        center.dx - visualWidthFor(input) / 2,
        center.dy - nodeRadius,
        visualWidthFor(input),
        visualHeightFor(input),
      );
}

@immutable
class ContactNetworkLayoutResult {
  const ContactNetworkLayoutResult({
    required this.mapSize,
    required this.usesInteractiveViewer,
    required this.metrics,
    required this.localCenter,
    required this.contactCenters,
    required this.ringExtents,
    required this.inputById,
  });

  final Size mapSize;
  final bool usesInteractiveViewer;
  final ContactNetworkLayoutMetrics metrics;
  final Offset localCenter;
  final Map<int, Offset> contactCenters;

  /// Orbit half-extents (x,y) actually holding nodes, for the orbit guides.
  final List<Size> ringExtents;
  final Map<int, ContactNetworkLayoutInput> inputById;
}

/// Pure, deterministic geometry for the map. It sees contact ids, measured
/// display-name bounds, viewport size, and normalized pin hints only.
class ContactNetworkLayout {
  static final _goldenAngle = math.pi * (3 - math.sqrt(5));

  static ContactNetworkLayoutResult resolve({
    required List<ContactNetworkLayoutInput> contacts,
    required Size safeViewport,
    required Size localLabelSize,
    Map<int, Offset> savedPins = const <int, Offset>{},
  }) {
    final ordered = List<ContactNetworkLayoutInput>.of(contacts)
      ..sort(_compareByDisplayName);
    final maxLabel = _maxLabelSize(ordered);

    if (ordered.length <= 1) {
      final metrics = ContactNetworkLayoutMetrics(
        mapSize: safeViewport,
        nodeDiameter: ContactNetworkLayoutMetrics.idealNodeDiameter,
        localLabelSize: localLabelSize,
        maxContactLabelSize: maxLabel,
      );
      return _place(ordered, metrics, savedPins, usesInteractiveViewer: false);
    }

    for (
      var diameter = ContactNetworkLayoutMetrics.idealNodeDiameter;
      diameter >= ContactNetworkLayoutMetrics.nodeFloorDiameter;
      diameter -= 2
    ) {
      final metrics = ContactNetworkLayoutMetrics(
        mapSize: safeViewport,
        nodeDiameter: diameter,
        localLabelSize: localLabelSize,
        maxContactLabelSize: maxLabel,
      );
      final required = _requiredExtent(ordered, metrics);
      if (required.width <= safeViewport.width &&
          required.height <= safeViewport.height) {
        return _place(
          ordered,
          metrics,
          savedPins,
          usesInteractiveViewer: false,
        );
      }
    }

    final floorMetrics = ContactNetworkLayoutMetrics(
      mapSize: safeViewport,
      nodeDiameter: ContactNetworkLayoutMetrics.nodeFloorDiameter,
      localLabelSize: localLabelSize,
      maxContactLabelSize: maxLabel,
    );
    final required = _requiredExtent(ordered, floorMetrics);
    final mapSize = Size(
      math.max(safeViewport.width, required.width),
      math.max(safeViewport.height, required.height),
    );
    final metrics = ContactNetworkLayoutMetrics(
      mapSize: mapSize,
      nodeDiameter: ContactNetworkLayoutMetrics.nodeFloorDiameter,
      localLabelSize: localLabelSize,
      maxContactLabelSize: maxLabel,
    );
    return _place(ordered, metrics, savedPins, usesInteractiveViewer: true);
  }

  static ContactNetworkLayoutResult _place(
    List<ContactNetworkLayoutInput> ordered,
    ContactNetworkLayoutMetrics metrics,
    Map<int, Offset> savedPins, {
    required bool usesInteractiveViewer,
  }) {
    final localBounds = metrics.localCenterBounds;
    final localCenter = ordered.length == 1
        ? Offset(
            _lerp(localBounds.left, localBounds.right, 0.30),
            _lerp(localBounds.top, localBounds.bottom, 0.70),
          )
        : localBounds.center;
    final centers = <int, Offset>{};

    if (ordered.length == 1) {
      final contact = ordered.single;
      final bounds = metrics.centerBoundsFor(contact);
      final saved = savedPins[contact.id];
      final preferred = saved == null
          ? Offset(
              _lerp(bounds.left, bounds.right, 0.70),
              _lerp(bounds.top, bounds.bottom, 0.26),
            )
          : fromNormalized(saved, metrics, contact);
      final resolvedCenter = clampCenter(preferred, metrics, contact);
      centers[contact.id] = resolvedCenter;
      final orbit = (resolvedCenter - localCenter).distance;
      return ContactNetworkLayoutResult(
        mapSize: metrics.mapSize,
        usesInteractiveViewer: usesInteractiveViewer,
        metrics: metrics,
        localCenter: localCenter,
        contactCenters: centers,
        ringExtents: [Size(orbit, orbit)],
        inputById: <int, ContactNetworkLayoutInput>{contact.id: contact},
      );
    }

    final rings = _ringsFor(
      ordered,
      metrics,
      expandIntoViewport: !usesInteractiveViewer,
    );
    // The local node and its caption participate in collision resolution so
    // contacts never crowd or overlap the network's origin.
    final occupied = <Rect>[
      Rect.fromLTWH(
        localCenter.dx - metrics.localVisualWidth / 2,
        localCenter.dy - metrics.localNodeRadius,
        metrics.localVisualWidth,
        ContactNetworkLayoutMetrics.localNodeDiameter +
            ContactNetworkLayoutMetrics.labelGap +
            metrics.localLabelSize.height,
      ),
    ];
    for (final ring in rings) {
      for (var index = 0; index < ring.contacts.length; index++) {
        final contact = ring.contacts[index];
        final saved = savedPins[contact.id];
        final angle =
            index * _goldenAngle + (_unitHash(contact.id) - 0.5) * 0.36;
        final preferred = saved == null
            ? Offset(
                localCenter.dx + math.cos(angle) * ring.radiusX,
                localCenter.dy + math.sin(angle) * ring.radiusY,
              )
            : fromNormalized(saved, metrics, contact);
        final resolved = _resolveCollision(
          clampCenter(preferred, metrics, contact),
          metrics,
          contact,
          occupied,
          index,
        );
        centers[contact.id] = resolved;
        occupied.add(metrics.visualRectFor(contact, resolved));
      }
    }

    return ContactNetworkLayoutResult(
      mapSize: metrics.mapSize,
      usesInteractiveViewer: usesInteractiveViewer,
      metrics: metrics,
      localCenter: localCenter,
      contactCenters: centers,
      ringExtents: [for (final ring in rings) Size(ring.radiusX, ring.radiusY)],
      inputById: <int, ContactNetworkLayoutInput>{
        for (final contact in ordered) contact.id: contact,
      },
    );
  }

  static List<_ContactRing> _ringsFor(
    List<ContactNetworkLayoutInput> contacts,
    ContactNetworkLayoutMetrics metrics, {
    bool expandIntoViewport = false,
  }) {
    final minSpacing = math.max(
      metrics.maxVisualWidth + 8,
      metrics.nodeDiameter + 12,
    );
    final radialSpacing = math.max(minSpacing, metrics.maxVisualHeight + 8);
    final maximumRadiusX = (metrics.mapSize.width - metrics.maxVisualWidth) / 2;
    final maximumRadiusY =
        (metrics.mapSize.height - metrics.maxVisualHeight) / 2;
    final rings = <_ContactRing>[];
    var offset = 0;
    var ringIndex = 0;
    while (offset < contacts.length) {
      final baseRadius = radialSpacing * (ringIndex + 1);
      final fraction = ringIndex == 0
          ? 0.55
          : math.min(0.95, 0.55 + ringIndex * 0.40);
      final radiusX = expandIntoViewport
          ? math.max(baseRadius, maximumRadiusX * fraction)
          : baseRadius;
      final radiusY = expandIntoViewport
          ? math.max(baseRadius, maximumRadiusY * fraction)
          : baseRadius;
      final mean = math.sqrt((radiusX * radiusX + radiusY * radiusY) / 2);
      final capacity = math.max(1, (2 * math.pi * mean / minSpacing).floor());
      final end = math.min(contacts.length, offset + capacity);
      rings.add(_ContactRing(radiusX, radiusY, contacts.sublist(offset, end)));
      offset = end;
      ringIndex++;
    }
    // A lone ring earns a wider orbit: breathe into the viewport instead of
    // hugging the local node.
    if (expandIntoViewport && rings.length == 1) {
      final only = rings.first;
      rings[0] = _ContactRing(
        math.max(only.radiusX, maximumRadiusX * 0.72),
        math.max(only.radiusY, maximumRadiusY * 0.72),
        only.contacts,
      );
    }
    return rings;
  }

  static Size _requiredExtent(
    List<ContactNetworkLayoutInput> contacts,
    ContactNetworkLayoutMetrics metrics,
  ) {
    if (contacts.length <= 1) return metrics.mapSize;
    final rings = _ringsFor(contacts, metrics);
    final outer = rings.last;
    final width = 2 * (outer.radiusX + metrics.maxVisualWidth / 2);
    final height = 2 * (outer.radiusY + metrics.maxVisualHeight / 2);
    return Size(width, height);
  }

  static Offset _resolveCollision(
    Offset preferred,
    ContactNetworkLayoutMetrics metrics,
    ContactNetworkLayoutInput contact,
    List<Rect> occupied,
    int index,
  ) {
    final candidates = <Offset>[preferred];
    final stepSize = math.max(
      metrics.visualWidthFor(contact),
      metrics.visualHeightFor(contact),
    );
    for (var ring = 1; ring <= 14; ring++) {
      final distance = ring * stepSize * 0.55;
      for (var step = 0; step < 12; step++) {
        final angle =
            ((step + (index.isOdd ? 0.5 : 0)) * 2 * math.pi) / 12;
        candidates.add(
          Offset(
            preferred.dx + math.cos(angle) * distance,
            preferred.dy + math.sin(angle) * distance,
          ),
        );
      }
    }

    // Deterministic full-bounds sweep: broadens candidate coverage beyond
    // the preferred point's vicinity (row-major, stable across builds). The
    // coarse stride can still miss narrow gaps; the least-overlap fallback
    // below handles exhausted/impossible layouts.
    final sweepBounds = metrics.centerBoundsFor(contact);
    final sweepStep = stepSize * 0.6;
    for (var y = sweepBounds.top; y <= sweepBounds.bottom; y += sweepStep) {
      for (var x = sweepBounds.left; x <= sweepBounds.right; x += sweepStep) {
        candidates.add(Offset(x, y));
      }
    }

    // First clean candidate wins; otherwise keep the least-overlapping one
    // rather than surrendering to the preferred point.
    Offset? best;
    var bestOverlap = double.infinity;
    for (final candidate in candidates) {
      final clamped = clampCenter(candidate, metrics, contact);
      final rect = metrics.visualRectFor(contact, clamped).inflate(4);
      var overlap = 0.0;
      for (final other in occupied) {
        final intersection = rect.intersect(other.inflate(4));
        if (intersection.width > 0 && intersection.height > 0) {
          overlap += intersection.width * intersection.height;
        }
      }
      if (overlap == 0) return clamped;
      if (overlap < bestOverlap) {
        bestOverlap = overlap;
        best = clamped;
      }
    }
    return best ?? clampCenter(preferred, metrics, contact);
  }

  static Offset clampCenter(
    Offset center,
    ContactNetworkLayoutMetrics metrics,
    ContactNetworkLayoutInput contact,
  ) {
    final bounds = metrics.centerBoundsFor(contact);
    return Offset(
      center.dx.clamp(bounds.left, bounds.right).toDouble(),
      center.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
  }

  static Offset toNormalized(
    Offset center,
    ContactNetworkLayoutMetrics metrics,
    ContactNetworkLayoutInput contact,
  ) {
    final bounds = metrics.centerBoundsFor(contact);
    return Offset(
      _inverseLerp(bounds.left, bounds.right, center.dx),
      _inverseLerp(bounds.top, bounds.bottom, center.dy),
    );
  }

  static Offset fromNormalized(
    Offset normalized,
    ContactNetworkLayoutMetrics metrics,
    ContactNetworkLayoutInput contact,
  ) {
    final bounds = metrics.centerBoundsFor(contact);
    return Offset(
      _lerp(bounds.left, bounds.right, normalized.dx.clamp(0, 1).toDouble()),
      _lerp(bounds.top, bounds.bottom, normalized.dy.clamp(0, 1).toDouble()),
    );
  }

  static int _compareByDisplayName(
    ContactNetworkLayoutInput a,
    ContactNetworkLayoutInput b,
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

  static List<ContactNetworkLayoutInput> sortContacts(
    List<ContactNetworkLayoutInput> contacts,
  ) {
    final sorted = List<ContactNetworkLayoutInput>.of(contacts)
      ..sort(_compareByDisplayName);
    return sorted;
  }

  static Size _maxLabelSize(List<ContactNetworkLayoutInput> contacts) {
    if (contacts.isEmpty) return Size.zero;
    return Size(
      contacts.map((contact) => contact.labelSize.width).reduce(math.max),
      contacts.map((contact) => contact.labelSize.height).reduce(math.max),
    );
  }

  static double _unitHash(int value) {
    var hash = value;
    hash = ((hash >> 16) ^ hash) * 0x45d9f3b;
    hash = ((hash >> 16) ^ hash) * 0x45d9f3b;
    hash = (hash >> 16) ^ hash;
    return (hash & 0x7fffffff) / 0x7fffffff;
  }

  static double _lerp(double start, double end, double t) =>
      start + (end - start) * t;

  static double _inverseLerp(double start, double end, double value) {
    if (start == end) return 0.5;
    return ((value - start) / (end - start)).clamp(0, 1).toDouble();
  }
}

class _ContactRing {
  const _ContactRing(this.radiusX, this.radiusY, this.contacts);

  final double radiusX;
  final double radiusY;
  final List<ContactNetworkLayoutInput> contacts;
}

class _NetworkNode extends StatelessWidget {
  const _NetworkNode({
    required this.centerLabel,
    required this.caption,
    required this.seed,
    required this.isLocal,
    required this.nodeDiameter,
    required this.labelWidth,
    required this.labelStyle,
    required this.surfaceColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.accentColor,
    this.isFocused = false,
  });

  final String centerLabel;
  final String caption;
  final int seed;
  final bool isLocal;
  final double nodeDiameter;
  final double labelWidth;
  final TextStyle labelStyle;
  final Color surfaceColor;
  final Color borderColor;
  final Color foregroundColor;
  final Color accentColor;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final initialsStyle = RpgTheme.bodyFont(
      fontSize: isLocal
          ? 16.0
          : (nodeDiameter * 0.22).clamp(11.0, 15.0).toDouble(),
      fontWeight: FontWeight.w800,
      color: isLocal ? accentColor : foregroundColor,
    );
    final Widget core;
    if (isLocal) {
      core = CustomPaint(
        foregroundPainter: _LocalReticlePainter(
          borderColor: borderColor,
          accent: accentColor,
          focused: isFocused,
        ),
        child: ClipOval(
          child: ColoredBox(
            color: surfaceColor,
            child: Center(child: Text(centerLabel, style: initialsStyle)),
          ),
        ),
      );
    } else {
      core = CustomPaint(
        foregroundPainter: _TerminalChromePainter(
          borderColor: borderColor,
          accent: accentColor,
          focused: isFocused,
        ),
        child: ClipPath(
          clipper: const _ClippedCornerClipper(),
          child: ColoredBox(
            color: surfaceColor,
            child: CustomPaint(
              foregroundPainter: _IdenticonPainter(
                seed: seed,
                color: foregroundColor,
              ),
              child: Align(
                alignment: const Alignment(0, 0.45),
                child: Text(centerLabel, style: initialsStyle),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: labelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: nodeDiameter, height: nodeDiameter, child: core),
          const SizedBox(height: ContactNetworkLayoutMetrics.labelGap),
          Text(caption, softWrap: false, style: labelStyle),
        ],
      ),
    );
  }
}

/// Shared silhouette for the terminal nodes: a rectangle with 45-degree
/// clipped corners.
Path _clippedCornerPath(Rect rect, double corner) => Path()
  ..moveTo(rect.left + corner, rect.top)
  ..lineTo(rect.right - corner, rect.top)
  ..lineTo(rect.right, rect.top + corner)
  ..lineTo(rect.right, rect.bottom - corner)
  ..lineTo(rect.right - corner, rect.bottom)
  ..lineTo(rect.left + corner, rect.bottom)
  ..lineTo(rect.left, rect.bottom - corner)
  ..lineTo(rect.left, rect.top + corner)
  ..close();

class _ClippedCornerClipper extends CustomClipper<Path> {
  const _ClippedCornerClipper();

  @override
  Path getClip(Size size) => _clippedCornerPath(Offset.zero & size, 9);

  @override
  bool shouldReclip(covariant _ClippedCornerClipper oldClipper) => false;
}

/// Symmetric 5x5 identicon: the left three columns come from hash bits and
/// mirror to the right. Symmetry reads as designed identity, not noise.
class _IdenticonPainter extends CustomPainter {
  const _IdenticonPainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final grid = side * 0.36;
    final cell = grid / 5;
    final left = (size.width - grid) / 2;
    final top = side * 0.10;
    final paint = Paint()..color = color.withValues(alpha: 0.30);
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 5; col++) {
        final src = col < 3 ? col : 4 - col;
        if (((seed >> (row * 3 + src)) & 1) == 1) {
          canvas.drawRect(
            Rect.fromLTWH(
              left + col * cell + 0.5,
              top + row * cell + 0.5,
              cell - 1,
              cell - 1,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IdenticonPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.color != color;
}

/// Terminal-node chrome: base silhouette stroke, reinforced clipped corners,
/// an inner inset hairline frame, and a focus halo. Painted unclipped so the
/// halo and corner strokes stay crisp.
class _TerminalChromePainter extends CustomPainter {
  const _TerminalChromePainter({
    required this.borderColor,
    required this.accent,
    required this.focused,
  });

  final Color borderColor;
  final Color accent;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    const corner = 9.0;
    const armLen = 6.0;
    final rect = (Offset.zero & size).deflate(0.75);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    stroke
      ..strokeWidth = 1.25
      ..color = borderColor.withValues(alpha: 0.55);
    canvas.drawPath(_clippedCornerPath(rect, corner), stroke);

    stroke
      ..strokeWidth = 2
      ..color = borderColor.withValues(alpha: 0.9);
    for (final c in <(Offset, Offset, Offset, Offset)>[
      (
        Offset(rect.left + corner, rect.top),
        Offset(rect.left, rect.top + corner),
        const Offset(armLen, 0),
        const Offset(0, armLen),
      ),
      (
        Offset(rect.right - corner, rect.top),
        Offset(rect.right, rect.top + corner),
        const Offset(-armLen, 0),
        const Offset(0, armLen),
      ),
      (
        Offset(rect.right, rect.bottom - corner),
        Offset(rect.right - corner, rect.bottom),
        const Offset(0, -armLen),
        const Offset(-armLen, 0),
      ),
      (
        Offset(rect.left + corner, rect.bottom),
        Offset(rect.left, rect.bottom - corner),
        const Offset(0, -armLen),
        const Offset(armLen, 0),
      ),
    ]) {
      canvas.drawLine(c.$1, c.$2, stroke);
      canvas.drawLine(c.$1, c.$1 + c.$3, stroke);
      canvas.drawLine(c.$2, c.$2 + c.$4, stroke);
    }

    stroke
      ..strokeWidth = 1
      ..color = borderColor.withValues(alpha: 0.25);
    canvas.drawPath(_clippedCornerPath(rect.deflate(3), corner - 2), stroke);

    if (focused) {
      stroke
        ..strokeWidth = 1
        ..color = accent;
      canvas.drawPath(_clippedCornerPath(rect.inflate(3.5), corner + 2), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TerminalChromePainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.accent != accent ||
      oldDelegate.focused != focused;
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

    stroke
      ..strokeWidth = 1
      ..color = borderColor;
    canvas.drawCircle(c, r - 0.5, stroke);

    stroke
      ..strokeWidth = 1.5
      ..color = accent;
    canvas.drawCircle(c, r - 6, stroke);

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

/// Link routing: PCB-style doglegs from the local ring into a port on the
/// contact node's facing edge.
class _TraceGeometry {
  static const double portStub = 4.0;

  /// Port on the square node edge facing [local], plus its outward normal.
  static (Offset, Offset) portFor(Offset local, Offset nodeCenter, double half) {
    final d = local - nodeCenter;
    if (d.dx.abs() >= d.dy.abs()) {
      final sx = d.dx >= 0 ? 1.0 : -1.0;
      return (Offset(nodeCenter.dx + sx * half, nodeCenter.dy), Offset(sx, 0));
    }
    final sy = d.dy >= 0 ? 1.0 : -1.0;
    return (Offset(nodeCenter.dx, nodeCenter.dy + sy * half), Offset(0, sy));
  }

  /// Leaves the local ring at 45 degrees, takes ONE bend, and arrives
  /// axis-aligned through a perpendicular stub into the port. Falls back to a
  /// straight run when the dogleg would double back on itself.
  static Path trace(
    Offset local,
    double localRadius,
    Offset port,
    Offset normal,
  ) {
    final entry = port + normal * portStub;
    final d = entry - local;
    Offset bend;
    if (normal.dy == 0) {
      final sx = d.dx >= 0 ? 1.0 : -1.0;
      bend = Offset(local.dx + sx * d.dy.abs(), entry.dy);
    } else {
      final sy = d.dy >= 0 ? 1.0 : -1.0;
      bend = Offset(entry.dx, local.dy + sy * d.dx.abs());
    }
    final doglegLen = (bend - local).distance + (entry - bend).distance;
    if (doglegLen > d.distance * 1.55) bend = Offset.lerp(local, entry, 0.5)!;
    final first = bend - local;
    final start = first.distance == 0
        ? local
        : local + first / first.distance * localRadius;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(bend.dx, bend.dy)
      ..lineTo(entry.dx, entry.dy)
      ..lineTo(port.dx, port.dy);
  }
}

/// Screen-fixed corner brackets framing the map viewport.
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
      (Offset(size.width - inset, inset), const Offset(-1, 0), const Offset(0, 1)),
      (Offset(inset, size.height - inset), const Offset(1, 0), const Offset(0, -1)),
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

/// The map's ambient field and link layer: sparse falloff ticks, dashed orbit
/// rings, dogleg traces with crafted endpoints, and the one-shot pulse.
class _ContactNetworkBackgroundPainter extends CustomPainter {
  const _ContactNetworkBackgroundPainter({
    required this.localCenter,
    required this.contactCenters,
    required this.squareHalf,
    required this.localRadius,
    required this.ringExtents,
    required this.baseColor,
    required this.accent,
    required this.conversationIds,
    required this.pulseProgress,
    required this.focusedId,
  });

  final Offset localCenter;
  final Map<int, Offset> contactCenters;
  final double squareHalf;
  final double localRadius;
  final List<Size> ringExtents;
  final Color baseColor;
  final Color accent;
  final Set<int> conversationIds;
  final double pulseProgress;
  final int? focusedId;

  @override
  void paint(Canvas canvas, Size size) {
    // Sparse '+' ticks with radial falloff: the field belongs to the local node.
    const tickSpacing = 56.0;
    const tickArm = 2.5;
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    final maxDist = corners
        .map((corner) => (corner - localCenter).distance)
        .reduce(math.max);
    final tickPaint = Paint()..strokeWidth = 1;
    for (var x = tickSpacing / 2; x < size.width; x += tickSpacing) {
      for (var y = tickSpacing / 2; y < size.height; y += tickSpacing) {
        final t = ((Offset(x, y) - localCenter).distance / maxDist) / 0.75;
        if (t >= 1) continue;
        tickPaint.color = baseColor.withValues(alpha: 0.12 * (1 - t));
        canvas.drawLine(Offset(x - tickArm, y), Offset(x + tickArm, y), tickPaint);
        canvas.drawLine(Offset(x, y - tickArm), Offset(x, y + tickArm), tickPaint);
      }
    }

    // Hairline dashed orbit rings: the map explains its own geometry.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = baseColor.withValues(alpha: 0.12);
    for (final extent in ringExtents) {
      const dash = 6.0;
      const gap = 10.0;
      final mean = math.sqrt(
        (extent.width * extent.width + extent.height * extent.height) / 2,
      );
      if (mean < 1) continue;
      final rect = Rect.fromCenter(
        center: localCenter,
        width: extent.width * 2,
        height: extent.height * 2,
      );
      final count = math.max(8, (2 * math.pi * mean / (dash + gap)).floor());
      final step = 2 * math.pi / count;
      // The one-contact hero orbit renders only as a short dashed arc around
      // the contact — the full circle's off-screen remainder would surface as
      // stray fragments at the viewport edges.
      final heroAngle = contactCenters.length == 1
          ? (contactCenters.values.single - localCenter).direction
          : null;
      for (var i = 0; i < count; i++) {
        final angle = i * step;
        if (heroAngle != null) {
          final delta =
              (angle - heroAngle + math.pi) % (2 * math.pi) - math.pi;
          if (delta.abs() > 0.35) continue;
        }
        canvas.drawArc(rect, angle, dash / mean, false, ringPaint);
      }
    }

    // Traces with real-data hierarchy and crafted endpoints.
    final isHero = contactCenters.length == 1;
    final tracePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHero ? 1.4 : 1.0
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final padPaint = Paint();
    contactCenters.forEach((id, center) {
      final (port, normal) = _TraceGeometry.portFor(
        localCenter,
        center,
        squareHalf,
      );
      final path = _TraceGeometry.trace(localCenter, localRadius, port, normal);
      final hasConv = conversationIds.contains(id);
      final focusedTrace = id == focusedId;
      final alpha = focusedTrace
          ? 0.80
          : isHero
          ? 0.70
          : hasConv
          ? 0.45
          : 0.30;
      tracePaint.color = (focusedTrace || isHero ? accent : baseColor)
          .withValues(alpha: alpha);
      if (hasConv) {
        // Doubled trace: two hairlines 1.5px apart (whole-canvas translate;
        // the corner offset error at this width is imperceptible).
        final perp = Offset(-normal.dy, normal.dx) * 0.75;
        canvas.save();
        canvas.translate(perp.dx, perp.dy);
        canvas.drawPath(path, tracePaint);
        canvas.restore();
        canvas.save();
        canvas.translate(-perp.dx, -perp.dy);
        canvas.drawPath(path, tracePaint);
        canvas.restore();
      } else {
        canvas.drawPath(path, tracePaint);
      }
      padPaint.color = (isHero ? accent : baseColor).withValues(
        alpha: math.min(1.0, alpha + 0.15),
      );
      final startTangent = path.computeMetrics().first.getTangentForOffset(0)!;
      canvas.drawRect(
        Rect.fromCenter(center: startTangent.position, width: 3, height: 3),
        padPaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: port, width: 2.5, height: 2.5),
        padPaint,
      );
    });

    // One-shot pulse with a fading tail along the bent path of every trace.
    if (pulseProgress < 1) {
      final pulsePaint = Paint();
      contactCenters.forEach((id, center) {
        final (port, normal) = _TraceGeometry.portFor(
          localCenter,
          center,
          squareHalf,
        );
        final metric = _TraceGeometry.trace(
          localCenter,
          localRadius,
          port,
          normal,
        ).computeMetrics().first;
        for (var i = 0; i < 4; i++) {
          final p = pulseProgress - i * 0.045;
          if (p <= 0) continue;
          pulsePaint.color = accent.withValues(
            alpha: (1 - i * 0.28) * (1 - pulseProgress * 0.3),
          );
          canvas.drawCircle(
            metric.getTangentForOffset(metric.length * p)!.position,
            i == 0 ? 2.2 : 1.4,
            pulsePaint,
          );
        }
      });
    }
  }

  @override
  bool shouldRepaint(covariant _ContactNetworkBackgroundPainter oldDelegate) =>
      oldDelegate.localCenter != localCenter ||
      oldDelegate.squareHalf != squareHalf ||
      oldDelegate.localRadius != localRadius ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.accent != accent ||
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.focusedId != focusedId ||
      !mapEquals(oldDelegate.contactCenters, contactCenters) ||
      !setEquals(oldDelegate.conversationIds, conversationIds) ||
      !listEquals(oldDelegate.ringExtents, ringExtents);
}

int _stableHash(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash << 5) - hash) + codeUnit;
    hash &= 0x7fffffff;
  }
  return hash;
}
