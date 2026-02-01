import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../config/app_config.dart';

class AvatarCircle extends StatefulWidget {
  final String email;
  final double radius;
  final String? profilePictureUrl;

  const AvatarCircle({
    super.key,
    required this.email,
    this.radius = 22,
    this.profilePictureUrl,
  });

  @override
  State<AvatarCircle> createState() => _AvatarCircleState();
}

class _AvatarCircleState extends State<AvatarCircle> {
  bool _imageLoadError = false;

  @override
  void didUpdateWidget(AvatarCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset error state when profilePictureUrl changes
    if (oldWidget.profilePictureUrl != widget.profilePictureUrl) {
      _imageLoadError = false;
    }
  }

  String _buildImageUrl() {
    final url = widget.profilePictureUrl;
    if (url == null || url.trim().isEmpty) return '';
    final isAbsolute =
        url.startsWith('http://') || url.startsWith('https://');
    final base = isAbsolute ? url : '${AppConfig.baseUrl}$url';
    return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.email.isNotEmpty ? widget.email[0].toUpperCase() : '?';
    final isDark = RpgTheme.isDark(context);
    final gradientColors = isDark
        ? const [RpgTheme.purple, RpgTheme.gold]
        : const [RpgTheme.primaryLight, RpgTheme.primaryLightHover];
    final letterColor =
        isDark ? RpgTheme.background : Colors.white;

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
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
          ),
          child: widget.profilePictureUrl != null && !_imageLoadError
              ? ClipOval(
                  child: Image.network(
                    _buildImageUrl(),
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          letter,
                          style: RpgTheme.bodyFont(
                            fontSize: widget.radius * 0.8,
                            color: letterColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradientColors,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? RpgTheme.gold : Colors.white,
                          ),
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
                      color: letterColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
