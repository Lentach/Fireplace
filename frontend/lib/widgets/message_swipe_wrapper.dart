import 'package:flutter/material.dart';

/// Wraps a message bubble with swipe gestures:
/// - Swipe left = Reply (icon revealed on right as content slides left)
/// - Swipe right = no action
/// - Long-press = onLongPress (e.g. context menu)
class MessageSwipeWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeReply;
  final VoidCallback onLongPress;
  final bool isMine;

  const MessageSwipeWrapper({
    super.key,
    required this.child,
    required this.onSwipeReply,
    required this.onLongPress,
    required this.isMine,
  });

  @override
  State<MessageSwipeWrapper> createState() => _MessageSwipeWrapperState();
}

class _MessageSwipeWrapperState extends State<MessageSwipeWrapper> {
  static const double _thresholdPx = 60;
  static const double _iconRevealPx = 80;

  double _dragOffset = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    setState(() {
      _dragOffset += details.delta.dx;
      _dragOffset = _dragOffset.clamp(-_iconRevealPx * 1.5, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!mounted) return;
    if (_dragOffset <= -_thresholdPx) {
      widget.onSwipeReply();
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final replyBg = accentColor.withValues(alpha: 0.15);

    return LayoutBuilder(
      builder: (context, constraints) {
        final childWidth = constraints.maxWidth;
        return GestureDetector(
          onLongPress: widget.onLongPress,
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          behavior: HitTestBehavior.opaque,
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: childWidth,
              child: Stack(
                alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: Offstage(
                      offstage: _dragOffset == 0,
                      child: Row(
                        children: [
                          const Spacer(),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _dragOffset < 0 ? (-_dragOffset).clamp(0, _iconRevealPx) : 0,
                            color: replyBg,
                            child: Center(
                              child: Icon(
                                Icons.reply,
                                color: _dragOffset <= -_thresholdPx
                                    ? accentColor
                                    : accentColor.withValues(alpha: 0.6),
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(_dragOffset, 0),
                    child: widget.child,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
