import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../config/app_config.dart';

class AvatarCircle extends StatefulWidget {
  final String email;
  final double radius;
  final String? profilePictureUrl;
  final bool showOnlineIndicator;
  final bool isOnline;

  const AvatarCircle({
    super.key,
    required this.email,
    this.radius = 22,
    this.profilePictureUrl,
    this.showOnlineIndicator = false,
    this.isOnline = false,
  });

  @override
  State<AvatarCircle> createState() => _AvatarCircleState();
}

class _AvatarCircleState extends State<AvatarCircle> {
  bool _imageLoadError = false;

  @override
  Widget build(BuildContext context) {
    final letter = widget.email.isNotEmpty ? widget.email[0].toUpperCase() : '?';

    return Stack(
      children: [
        // Main avatar
        Container(
          width: widget.radius * 2,
          height: widget.radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: widget.profilePictureUrl != null && !_imageLoadError
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [RpgTheme.purple, RpgTheme.gold],
                  ),
          ),
          child: widget.profilePictureUrl != null && !_imageLoadError
              ? ClipOval(
                  child: Image.network(
                    '${AppConfig.baseUrl}${widget.profilePictureUrl}?t=${DateTime.now().millisecondsSinceEpoch}',
                    width: widget.radius * 2,
                    height: widget.radius * 2,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _imageLoadError = true);
                        }
                      });
                      return Container(
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
                            fontSize: widget.radius * 0.8,
                            color: RpgTheme.background,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [RpgTheme.purple, RpgTheme.gold],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                          valueColor: const AlwaysStoppedAnimation(RpgTheme.gold),
                        ),
                      );
                    },
                  ),
                )
              : Container(
                  alignment: Alignment.center,
                  child: Text(
                    letter,
                    style: RpgTheme.bodyFont(
                      fontSize: widget.radius * 0.8,
                      color: RpgTheme.background,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),

        // Online indicator
        if (widget.showOnlineIndicator)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: widget.radius * 0.4,
              height: widget.radius * 0.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isOnline ? Colors.green : Colors.grey,
                border: Border.all(
                  color: RpgTheme.background,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
