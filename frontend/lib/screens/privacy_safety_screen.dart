import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/chat_provider.dart';
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
    final fp = await context.read<ChatProvider>().getIdentityFingerprint();
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
          AppLocalizations.of(context).privacySafetyTitle,
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
                AppLocalizations.of(context).e2eEncryptionEnabled,
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
              AppLocalizations.of(context).e2eEncryptionDescription,
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
              title: AppLocalizations.of(context).yourEncryptionKeys,
              description: AppLocalizations.of(context).yourEncryptionKeysDescription,
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.devices,
              title: AppLocalizations.of(context).singleDeviceEncryption,
              description: AppLocalizations.of(context).singleDeviceEncryptionDescription,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              _buildInfoCard(
                context,
                icon: Icons.laptop,
                title: AppLocalizations.of(context).webKeyStorage,
                description: AppLocalizations.of(context).webKeyStorageDescription,
              ),
            ],
            const SizedBox(height: 16),
            _buildInfoCard(
              context,
              icon: Icons.photo_library_outlined,
              title: AppLocalizations.of(context).whatIsEncrypted,
              description: AppLocalizations.of(context).whatIsEncryptedDescription,
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.info_outline,
              title: AppLocalizations.of(context).serverStoresMetadata,
              description: AppLocalizations.of(context).serverStoresMetadataDescription,
            ),
            const SizedBox(height: 32),

            // Fingerprint section
            if (!_loading && _fingerprint != null) ...[
              Text(
                AppLocalizations.of(context).yourIdentityFingerprint,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).shareFingerprintHint,
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
