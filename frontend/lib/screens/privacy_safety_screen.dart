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
import '../widgets/settings_console.dart';
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
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

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
          _diagLogUnlocked ? '🔓 hacker mode' : l10n.privacySafetyTitle,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top:
              MediaQuery.paddingOf(context).top +
              GlassTopBar.capsuleHeight +
              16,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Long-pressing the privacy terminal unlocks the E2E log.
                  Center(
                    child: Semantics(
                      button: true,
                      label: l10n.privacySafetyTitle,
                      onLongPress: () =>
                          setState(() => _diagLogUnlocked = true),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () =>
                            setState(() => _diagLogUnlocked = true),
                        child: SizedBox(
                          width: 88,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 72,
                                child: Center(
                                  child: const ConsoleHexIcon(
                                    glyph: ConsoleGlyph.privacy,
                                    height: 68,
                                  ),
                                ),
                              ),
                              if (_diagLogUnlocked) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '🔓 hacker mode',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.e2eEncryptionEnabled,
                    style: RpgTheme.bodyFont(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.e2eEncryptionDescription,
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SettingsSectionCaption(label: l10n.settingsSectionSecurity),
            ConsoleInfoRow(
              glyph: ConsoleGlyph.keys,
              title: l10n.yourEncryptionKeys,
              body: l10n.yourEncryptionKeysDescription,
            ),
            ConsoleInfoRow(
              glyph: ConsoleGlyph.devices,
              title: l10n.singleDeviceEncryption,
              body: l10n.singleDeviceEncryptionDescription,
            ),
            if (kIsWeb)
              ConsoleInfoRow(
                glyph: ConsoleGlyph.webStorage,
                title: l10n.webKeyStorage,
                body: l10n.webKeyStorageDescription,
              ),
            SettingsSectionCaption(label: l10n.privacySafetyTitle),
            ConsoleInfoRow(
              glyph: ConsoleGlyph.media,
              title: l10n.whatIsEncrypted,
              body: l10n.whatIsEncryptedDescription,
            ),
            ConsoleInfoRow(
              glyph: ConsoleGlyph.metadata,
              title: l10n.serverStoresMetadata,
              body: l10n.serverStoresMetadataDescription,
            ),
            ConsoleInfoRow(
              glyph: ConsoleGlyph.quantum,
              title: l10n.privacyAntiQuantumNoteTitle,
              body: l10n.privacyAntiQuantumNoteDescription,
            ),
            SettingsSectionCaption(label: l10n.settingsSectionPreferences),
            _buildLocalCacheCard(context),
            if (_loading || _fingerprint != null) ...[
              SettingsSectionCaption(label: l10n.yourIdentityFingerprint),
              if (!_loading && _fingerprint != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(kConsoleHexLeft, 0, 16, 0),
                  child: Text(
                    l10n.shareFingerprintHint,
                    style: RpgTheme.bodyFont(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(kConsoleHexLeft, 0, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: SelectableText(
                      _fingerprint!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
              if (_loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(kConsoleHexLeft, 0, 16, 0),
                  child: Semantics(
                    label: l10n.devicesLoading,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 168,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            if (_diagLogUnlocked) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(kConsoleHexLeft, 0, 16, 0),
                child: _buildDiagLogPanel(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalCacheCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsoleInfoRow(
          glyph: ConsoleGlyph.cache,
          title: l10n.localMessageCache,
          body: l10n.localMessageCacheDescription,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            kConsoleHexLeft + kConsoleHexWidth + 12,
            0,
            16,
            12,
          ),
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _clearingLocalCache ? null : _clearLocalMessageCache,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_clearingLocalCache) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(l10n.clearLocalMessageCache),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiagLogPanel(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;
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
        color: theme.colorScheme.surfaceContainerHighest,
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
