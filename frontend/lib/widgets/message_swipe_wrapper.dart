import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

/// Wraps a message bubble with swipe gestures:
/// - Swipe left = Reply (icon revealed on right as content slides left)
/// - Swipe right = Delete (icon revealed on left as content slides right)
/// - Long-press = onLongPress (e.g. emoji reactions)
class MessageSwipeWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeReply;
  final VoidCallback onSwipeDelete;
  final VoidCallback onLongPress;
  final bool isMine;

  const MessageSwipeWrapper({
    super.key,
    required this.child,
    required this.onSwipeReply,
    required this.onSwipeDelete,
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
      // Clamp to prevent over-drag
      _dragOffset = _dragOffset.clamp(-_iconRevealPx * 1.5, _iconRevealPx * 1.5);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!mounted) return;
    if (_dragOffset <= -_thresholdPx) {
      widget.onSwipeReply();
    } else if (_dragOffset >= _thresholdPx) {
      widget.onSwipeDelete();
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final replyBg = accentColor.withValues(alpha: 0.15);
    final deleteBg = Colors.red.withValues(alpha: 0.15);

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
                  // Background icons (visible ONLY during swipe; Offstage when idle)
                  Positioned.fill(
                    child: Offstage(
                      offstage: _dragOffset == 0,
                      child: Row(
                        children: [
                          // Delete zone (left) - revealed when swiping right
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _dragOffset > 0 ? _dragOffset.clamp(0, _iconRevealPx) : 0,
                            color: deleteBg,
                            child: Center(
                              child: Icon(
                                Icons.delete_outline,
                                color: _dragOffset >= _thresholdPx
                                    ? Colors.red
                                    : Colors.red.withValues(alpha: 0.6),
                                size: 24,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Reply zone (right) - revealed when swiping left
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
                  // Sliding child
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
