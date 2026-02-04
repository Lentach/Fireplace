import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import 'chat_action_tiles.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _hasText = false;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chat = context.read<ChatProvider>();
    final expiresIn = chat.conversationDisappearingTimer;
    chat.sendMessage(text, expiresIn: expiresIn);

    _controller.clear();

    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      // TODO: Upload image and send as message (Phase 5)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload coming soon')),
      );
    }
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
          // Action tiles row
          const ChatActionTiles(),

          // Input row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                // Attachment button (gallery)
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  iconSize: 24,
                  color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                  onPressed: _pickImageFromGallery,
                ),

                // Text field
                Expanded(
                  child: TextField(
                    controller: _controller,
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

                // Emoji button
                IconButton(
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                  ),
                  iconSize: 24,
                  color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
                  onPressed: _toggleEmojiPicker,
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

          // Emoji picker
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _controller.text += emoji.emoji;
                },
                config: Config(
                  // Use available parameters in emoji_picker_flutter 2.0.0
                  // Most styling is handled by the theme automatically
                ),
              ),
            ),
        ],
      ),
    );
  }
}
