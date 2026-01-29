import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class RpgTabBar extends StatelessWidget {
  final int activeIndex;
  final List<String> labels;
  final ValueChanged<int> onTap;

  const RpgTabBar({
    super.key,
    required this.activeIndex,
    required this.labels,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final isActive = i == activeIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              margin: EdgeInsets.only(right: i < labels.length - 1 ? 4 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? RpgTheme.activeTabBg : RpgTheme.tabBg,
                border: Border.all(
                  color: isActive ? RpgTheme.gold : RpgTheme.tabBorder,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: RpgTheme.pressStart2P(
                  fontSize: 9,
                  color: isActive ? RpgTheme.gold : RpgTheme.mutedText,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
