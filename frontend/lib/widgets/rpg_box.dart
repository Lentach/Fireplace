import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class RpgBox extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets padding;

  const RpgBox({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: RpgTheme.rpgOuterBorderDecoration(),
      padding: const EdgeInsets.all(8),
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: RpgTheme.rpgBoxDecoration(),
        child: child,
      ),
    );
  }
}
