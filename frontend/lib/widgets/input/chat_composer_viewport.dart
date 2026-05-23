import 'package:flutter/material.dart';

/// Builds the scrollable message list with [listBottomPadding] clearance for the
/// overlaid composer and keyboard inset.
typedef MessageListBuilder = Widget Function(double listBottomPadding);

/// Owns chat layout: messages fill the stack; [composer] is positioned at the
/// bottom above [MediaQuery.viewInsets]. List bottom padding tracks measured
/// composer height plus keyboard inset so [Expanded] does not shrink when the
/// composer grows (reply bar, action panel).
class ChatComposerViewport extends StatefulWidget {
  const ChatComposerViewport({
    super.key,
    required this.messageListBuilder,
    required this.composer,
  });

  final MessageListBuilder messageListBuilder;
  final Widget composer;

  @override
  State<ChatComposerViewport> createState() => _ChatComposerViewportState();
}

class _ChatComposerViewportState extends State<ChatComposerViewport> {
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  @override
  void didUpdateWidget(ChatComposerViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  void _measureComposer([Duration? _]) {
    if (!mounted) return;
    final renderObject = _composerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final height = renderObject.size.height;
    if (height != _composerHeight) {
      setState(() => _composerHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final listBottomPadding = _composerHeight + keyboardInset;

    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: widget.messageListBuilder(listBottomPadding),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboardInset,
          child: KeyedSubtree(
            key: _composerKey,
            child: widget.composer,
          ),
        ),
      ],
    );
  }
}
