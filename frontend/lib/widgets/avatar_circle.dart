import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class AvatarCircle extends StatelessWidget {
  final String email;
  final double radius;

  const AvatarCircle({
    super.key,
    required this.email,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final letter = email.isNotEmpty ? email[0].toUpperCase() : '?';
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RpgTheme.purple, RpgTheme.gold],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: RpgTheme.bodyFont(
          fontSize: radius * 0.8,
          color: RpgTheme.background,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
