import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

/// Shared top bar for main tabs (Chat, Contacts, Settings): full width,
/// fixed [kToolbarHeight] content below [SafeArea], centered title.
class MainTabScreenHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? trailing;

  const MainTabScreenHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  static const double horizontalPadding = 12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: FireplaceColors.of(context).convItemBorder,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                ?leading,
                Expanded(
                  child: Center(
                    child: Text(
                      title,
                      style: RpgTheme.screenHeaderTitle(
                        color: colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
