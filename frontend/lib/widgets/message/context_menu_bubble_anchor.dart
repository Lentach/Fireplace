import 'package:flutter/material.dart';

/// Bottom margin on the anchored bubble [Container] (chat + voice bubbles).
/// Subtracted from the anchor [RenderBox] height for overlay gap math so the
/// menu aligns to the painted bubble, not the layout margin slab.
const kContextMenuAnchorBottomMargin = 10.0;

/// Wraps the visible message bubble so context-menu overlays anchor to bubble
/// bounds, not the full-width swipe row.
class ContextMenuBubbleAnchor extends StatefulWidget {
  const ContextMenuBubbleAnchor({
    super.key,
    required this.child,
  });

  final Widget child;

  static RenderBox? renderBoxOf(BuildContext context) {
    final anchorState = _findAnchorStateInSubtree(context as Element);
    return anchorState?.renderBox;
  }

  static _ContextMenuBubbleAnchorState? _findAnchorStateInSubtree(Element element) {
    _ContextMenuBubbleAnchorState? found;
    void visit(Element el) {
      if (found != null) return;
      final state = el is StatefulElement ? el.state : null;
      if (state is _ContextMenuBubbleAnchorState) {
        found = state;
        return;
      }
      el.visitChildElements(visit);
    }

    visit(element);
    return found;
  }

  @override
  State<ContextMenuBubbleAnchor> createState() =>
      _ContextMenuBubbleAnchorState();
}

class _ContextMenuBubbleAnchorState extends State<ContextMenuBubbleAnchor> {
  final GlobalKey _key = GlobalKey();

  RenderBox? get renderBox =>
      _key.currentContext?.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
