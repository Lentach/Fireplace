import 'package:flutter/material.dart';
import '../services/encryption_service.dart';
import '../theme/rpg_theme.dart';

class PrivacySafetyScreen extends StatefulWidget {
  const PrivacySafetyScreen({super.key});

  @override
  State<PrivacySafetyScreen> createState() => _PrivacySafetyScreenState();
}

class _PrivacySafetyScreenState extends State<PrivacySafetyScreen> {
  String? _fingerprint;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final enc = EncryptionService();
    await enc.initialize();
    final fp = await enc.getIdentityFingerprint();
    if (mounted) {
      setState(() {
        _fingerprint = fp;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Privacy & Safety',
          style: RpgTheme.pressStart2P(
            fontSize: 12,
            color: theme.colorScheme.primary,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.primary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shield icon
            Center(
              child: Icon(
                Icons.verified_user,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Center(
              child: Text(
                'End-to-end encryption is enabled',
                style: RpgTheme.bodyFont(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // Description
            Text(
              'Your messages are encrypted using the Signal Protocol. '
              'Only you and the recipient can read them. '
              'Not even Fireplace servers can access your message content.',
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: mutedColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Key info section
            _buildInfoCard(
              context,
              icon: Icons.key,
              title: 'Your encryption keys',
              description:
                  'Keys are stored securely on this device. '
                  'If you switch devices or reinstall the app, '
                  'a new set of keys will be generated and previous '
                  'message history cannot be recovered.',
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.devices,
              title: 'Single-device encryption',
              description:
                  'Each device has its own encryption keys. '
                  'Messages are tied to the device that sent or received them.',
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.photo_library_outlined,
              title: 'What is encrypted',
              description:
                  'Text messages and link previews are end-to-end encrypted. '
                  'Media files (images, voice messages, drawings) are not '
                  'yet encrypted end-to-end.',
            ),
            const SizedBox(height: 32),

            // Fingerprint section
            if (!_loading && _fingerprint != null) ...[
              Text(
                'Your identity fingerprint',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share this with your contacts to verify your identity.',
                style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: SelectableText(
                  _fingerprint!,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: RpgTheme.bodyFont(
                    fontSize: 13,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
