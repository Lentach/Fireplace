import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import '../theme/rpg_theme.dart';
import '../utils/e2e_diag_log.dart';
import '../utils/e2e_persistent_diag.dart';
import '../widgets/audio/playback_controller.dart';
import '../widgets/glass/glass_top_bar.dart';
import '../widgets/top_snackbar.dart';

class PrivacySafetyScreen extends StatefulWidget {
  const PrivacySafetyScreen({super.key});

  @override
  State<PrivacySafetyScreen> createState() => _PrivacySafetyScreenState();
}

class _PrivacySafetyScreenState extends State<PrivacySafetyScreen> {
  String? _fingerprint;
  bool _loading = true;
  bool _clearingLocalCache = false;
  bool _diagLogUnlocked = false;
  String _diagFilter = 'current';

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final fp = await context
        .read<EncryptionProvider>()
        .getIdentityFingerprint();
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
    final mutedColor = isDark
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _diagLogUnlocked
              ? '🔓 hacker mode'
              : AppLocalizations.of(context).privacySafetyTitle,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + GlassTopBar.capsuleHeight + 16,
          24,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shield icon — long-press unlocks E2E diagnostic log
            Center(
              child: GestureDetector(
                onLongPress: () => setState(() => _diagLogUnlocked = true),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    if (_diagLogUnlocked) ...[
                      const SizedBox(height: 6),
                      Text(
                        '🔓 hacker mode',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
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
              style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Key info section
            _buildInfoCard(
              context,
              icon: Icons.key,
              title: AppLocalizations.of(context).yourEncryptionKeys,
              description: AppLocalizations.of(
                context,
              ).yourEncryptionKeysDescription,
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.devices,
              title: AppLocalizations.of(context).singleDeviceEncryption,
              description: AppLocalizations.of(
                context,
              ).singleDeviceEncryptionDescription,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              _buildInfoCard(
                context,
                icon: Icons.laptop,
                title: AppLocalizations.of(context).webKeyStorage,
                description: AppLocalizations.of(
                  context,
                ).webKeyStorageDescription,
              ),
            ],
            const SizedBox(height: 16),
            _buildInfoCard(
              context,
              icon: Icons.photo_library_outlined,
              title: AppLocalizations.of(context).whatIsEncrypted,
              description: AppLocalizations.of(
                context,
              ).whatIsEncryptedDescription,
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.info_outline,
              title: AppLocalizations.of(context).serverStoresMetadata,
              description: AppLocalizations.of(
                context,
              ).serverStoresMetadataDescription,
            ),
            const SizedBox(height: 16),

            _buildInfoCard(
              context,
              icon: Icons.science_outlined,
              title: AppLocalizations.of(context).privacyAntiQuantumNoteTitle,
              description: AppLocalizations.of(
                context,
              ).privacyAntiQuantumNoteDescription,
            ),
            const SizedBox(height: 16),
            _buildLocalCacheCard(context),
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
                  border: Border.all(color: theme.colorScheme.outlineVariant),
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
            if (_diagLogUnlocked) ...[
              const SizedBox(height: 24),
              _buildDiagLogPanel(context),
            ],
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
    final mutedColor = isDark
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;

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
                  style: RpgTheme.bodyFont(fontSize: 13, color: mutedColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalCacheCard(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor = isDark
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cleaning_services_outlined,
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.localMessageCache,
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.localMessageCacheDescription,
                      style: RpgTheme.bodyFont(fontSize: 13, color: mutedColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _clearingLocalCache ? null : _clearLocalMessageCache,
              icon: _clearingLocalCache
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(l10n.clearLocalMessageCache),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagLogPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor = isDark
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;
    final allEntries = E2eDiagLog.entries.reversed.toList();
    final durable = E2ePersistentDiag.entries.reversed.toList();
    final entries = switch (_diagFilter) {
      'historical' => durable,
      '24h' => E2eDiagLog.since(const Duration(hours: 24)).reversed.toList(),
      'build' => E2eDiagLog.since(
        DateTime.now().difference(E2eDiagLog.sessionStartedAt),
      ).reversed.toList(),
      'full' => [...durable, ...allEntries],
      _ => allEntries,
    };
    final failures = entries
        .where((e) => e.contains('FAIL') || e.contains('DECRYPT_DECISION'))
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.terminal, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'E2E Diagnostic Log',
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton(
                  onPressed: () async {
                    final all =
                        '== DURABLE FAILURES (survives restart) ==\n'
                        '${E2ePersistentDiag.entries.join('\n')}\n\n'
                        '== LIVE LOG ==\n'
                        '${E2eDiagLog.entries.join('\n')}';
                    await Clipboard.setData(ClipboardData(text: all));
                    if (!context.mounted) return;
                    showTopSnackBar(context, 'Log copied to clipboard');
                  },
                  child: const Text('Copy'),
                ),
                TextButton(
                  onPressed: () async {
                    E2eDiagLog.clear();
                    await E2ePersistentDiag.clear();
                    if (!mounted) return;
                    setState(() {});
                  },
                  child: const Text('Clear diagnostic logs only'),
                ),
              ],
            ),
          ),
          Text(
            'Current session: ${allEntries.length} events · failures: $failures',
          ),
          DropdownButton<String>(
            value: _diagFilter,
            items: const [
              DropdownMenuItem(
                value: 'current',
                child: Text('Current session'),
              ),
              DropdownMenuItem(
                value: 'build',
                child: Text('Since current build'),
              ),
              DropdownMenuItem(value: '24h', child: Text('Last 24 hours')),
              DropdownMenuItem(value: 'historical', child: Text('Historical')),
              DropdownMenuItem(value: 'full', child: Text('Full raw log')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _diagFilter = value);
            },
          ),
          if (E2eDiagLog.groupedFailures(entries).isNotEmpty) ...[
            const Text('Grouped failures'),
            ...E2eDiagLog.groupedFailures(entries).map(Text.new),
          ],
          const SizedBox(height: 8),
          const Text(
            'Clears diagnostic logs only. Does not clear messages, encryption keys, sessions, or browser storage.',
            style: TextStyle(fontSize: 11),
          ),
          if (durable.isNotEmpty) ...[
            Text(
              'Durable failures (survives restart)',
              style: RpgTheme.bodyFont(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: durable.length,
                itemBuilder: (context, index) => SelectableText(
                  durable[index],
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.error,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Live log',
              style: RpgTheme.bodyFont(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: entries.isEmpty
                ? Text(
                    'No events recorded',
                    style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (context, index) => SelectableText(
                      entries[index],
                      style: TextStyle(
                        fontSize: 11,
                        color: mutedColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearLocalMessageCache() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _clearingLocalCache = true);
    try {
      await PlaybackController.clearAudioCache();
      if (!mounted) return;
      showTopSnackBar(context, l10n.snackbarLocalMessageCacheCleared);
    } catch (_) {
      if (!mounted) return;
      showTopSnackBar(context, l10n.snackbarFailedToClearLocalMessageCache);
    } finally {
      if (mounted) {
        setState(() => _clearingLocalCache = false);
      }
    }
  }
}
