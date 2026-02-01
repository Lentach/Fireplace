import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/rpg_theme.dart';

class ProfilePictureDialog extends StatelessWidget {
  const ProfilePictureDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isDark ? RpgTheme.border : RpgTheme.convItemBorderLight;
    final mutedColor =
        isDark ? RpgTheme.mutedText : RpgTheme.textSecondaryLight;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose Photo',
              style: RpgTheme.pressStart2P(
                fontSize: 14,
                color: colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Take Photo
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: Text(
                'Take Photo',
                style: RpgTheme.bodyFont(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),

            // Choose from Gallery
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.photo_library, color: Colors.white),
              label: Text(
                'Choose from Gallery',
                style: RpgTheme.bodyFont(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),

            // Cancel
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: borderColor, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Cancel',
                style: RpgTheme.bodyFont(color: mutedColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
