import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import 'chat_action_tiles.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _showActionPanel = false;
  late final AnimationController _actionPanelController;
  late final Animation<double> _actionPanelAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
    _actionPanelController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _actionPanelAnimation = CurvedAnimation(
      parent: _actionPanelController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _actionPanelController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chat = context.read<ChatProvider>();
    final expiresIn = chat.conversationDisappearingTimer;
    chat.sendMessage(text, expiresIn: expiresIn);

    _controller.clear();
    // Keep focus on the text field so user can type the next message immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _toggleActionPanel() {
    setState(() {
      _showActionPanel = !_showActionPanel;
      if (_showActionPanel) {
        _actionPanelController.forward();
      } else {
        _actionPanelController.reverse();
      }
    });
  }

  void _recordVoice() {
    // TODO: Voice recording (future feature)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice messages coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;
    final inputBg = isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight;
    final tabBorderColor =
        isDark ? RpgTheme.tabBorderDark : RpgTheme.tabBorderLight;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                // Action panel toggle (arrow down/up)
                IconButton(
                  icon: Icon(
                    _showActionPanel
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  iconSize: 24,
                  color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                  onPressed: _toggleActionPanel,
                ),

                // Text field
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: tabBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: tabBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: RpgTheme.primaryColor(context),
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: inputBg,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),

                const SizedBox(width: 4),

                // Mic / Send toggle
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hasText
                        ? RpgTheme.primaryColor(context)
                        : Colors.transparent,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _hasText ? Icons.send_rounded : Icons.mic,
                      size: 22,
                    ),
                    color: _hasText
                        ? (isDark ? RpgTheme.accentDark : Colors.white)
                        : (isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight),
                    onPressed: _hasText ? _send : _recordVoice,
                  ),
                ),
              ],
            ),
          ),

          // Action tiles with slide animation
          SizeTransition(
            sizeFactor: _actionPanelAnimation,
            axisAlignment: -1.0,
            child: const ChatActionTiles(),
          ),
        ],
      ),
    );
  }
}
