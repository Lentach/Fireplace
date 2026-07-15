import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_top_bar.dart';

/// Square avatar crop step between the picker and the upload
/// (crop_your_image — pure Dart, identical rendering on web and native).
///
/// Pops with the cropped image as an [XFile], or with [fallback] (the
/// original picked file) if decoding/cropping fails — an exotic input format
/// must degrade to today's upload-as-picked behavior, never block the flow.
/// Pops with null when the user cancels.
class AvatarCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final XFile fallback;

  const AvatarCropScreen({
    super.key,
    required this.imageBytes,
    required this.fallback,
  });

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final CropController _controller = CropController();
  bool _cropping = false;

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        final png = _isPng(croppedImage);
        Navigator.of(context).pop(
          XFile.fromData(
            croppedImage,
            name: png ? 'avatar.png' : 'avatar.jpg',
            mimeType: png ? 'image/png' : 'image/jpeg',
          ),
        );
      case CropFailure():
        // Undecodable input: fall back to uploading the original file.
        Navigator.of(context).pop(widget.fallback);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        leading: IconButton(
          tooltip: l10n.userCardCancel,
          icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
          onPressed: _cropping ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.userCardCropPhoto,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: [
          _cropping
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: l10n.userCardSave,
                  icon: Icon(Icons.check, color: theme.colorScheme.primary),
                  onPressed: () {
                    setState(() => _cropping = true);
                    _controller.crop();
                  },
                ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + GlassTopBar.capsuleHeight + 24,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          left: 16,
          right: 16,
        ),
        child: Crop(
          image: widget.imageBytes,
          controller: _controller,
          aspectRatio: 1,
          withCircleUi: true,
          baseColor: theme.scaffoldBackgroundColor,
          maskColor: Colors.black.withValues(alpha: 0.55),
          progressIndicator: const CircularProgressIndicator(),
          onCropped: _onCropped,
        ),
      ),
    );
  }
}
