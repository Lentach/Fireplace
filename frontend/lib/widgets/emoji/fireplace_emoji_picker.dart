import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';

const kFireplaceSuggestedEmoji = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🔥',
  '👏',
  '🙏',
  '😍',
  '🧙',
];

class FireplaceEmojiPicker extends StatelessWidget {
  const FireplaceEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.onBackspacePressed,
    this.height = 320,
    this.showSuggestedRow = true,
  });

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback? onBackspacePressed;
  final double height;
  final bool showSuggestedRow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pickerHeight = showSuggestedRow ? height - 52 : height;

    return Semantics(
      label: l10n.emojiPickerSemantics,
      container: true,
      explicitChildNodes: true,
      child: Material(
        color: colorScheme.surface,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSuggestedRow)
                  _SuggestedEmojiRow(onEmojiSelected: onEmojiSelected),
                Expanded(
                  child: EmojiPicker(
                    onEmojiSelected: (_, emoji) => onEmojiSelected(emoji.emoji),
                    onBackspacePressed: onBackspacePressed,
                    config: Config(
                      height: pickerHeight,
                      locale: Localizations.localeOf(context),
                      checkPlatformCompatibility: true,
                      viewOrderConfig: const ViewOrderConfig(
                        top: EmojiPickerItem.searchBar,
                        middle: EmojiPickerItem.emojiView,
                        bottom: EmojiPickerItem.categoryBar,
                      ),
                      emojiTextStyle: TextStyle(
                        fontSize:
                            foundation.defaultTargetPlatform ==
                                TargetPlatform.iOS
                            ? 30
                            : 28,
                      ),
                      emojiViewConfig: EmojiViewConfig(
                        columns: MediaQuery.sizeOf(context).width < 420
                            ? 8
                            : 10,
                        emojiSizeMax:
                            foundation.defaultTargetPlatform ==
                                TargetPlatform.iOS
                            ? 32
                            : 30,
                        backgroundColor: colorScheme.surface,
                        gridPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        buttonMode: ButtonMode.MATERIAL,
                        noRecents: Center(
                          child: Text(
                            l10n.emojiPickerNoRecents,
                            style: RpgTheme.bodyFont(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: colorScheme.surface,
                        indicatorColor: RpgTheme.primaryColor(context),
                        iconColor: colorScheme.onSurfaceVariant,
                        iconColorSelected: RpgTheme.primaryColor(context),
                        backspaceColor: RpgTheme.primaryColor(context),
                        dividerColor: colorScheme.outline.withValues(
                          alpha: 0.22,
                        ),
                        extraTab: onBackspacePressed == null
                            ? CategoryExtraTab.NONE
                            : CategoryExtraTab.BACKSPACE,
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: colorScheme.surface,
                        buttonIconColor: RpgTheme.primaryColor(context),
                        hintText: l10n.emojiPickerSearchHint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestedEmojiRow extends StatelessWidget {
  const _SuggestedEmojiRow({required this.onEmojiSelected});

  final ValueChanged<String> onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: kFireplaceSuggestedEmoji.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final emoji = kFireplaceSuggestedEmoji[index];
            return Semantics(
              button: true,
              label: l10n.emojiPickerEmojiOptionSemantics(emoji),
              child: InkWell(
                key: ValueKey('emoji-picker-option-$emoji'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => onEmojiSelected(emoji),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
