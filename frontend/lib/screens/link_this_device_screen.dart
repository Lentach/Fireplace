import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/device_link/link_ceremony_controller.dart';
import '../services/device_link/link_crypto.dart';
import '../utils/link_fragment_stub.dart'
    if (dart.library.html) '../utils/link_fragment_web.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_top_bar.dart';
import '../widgets/top_snackbar.dart';

/// The NEW-DEVICE side (N) of the §5.1 link ceremony (Phase 2 T3).
///
/// Renders the out-of-band code BOTH as selectable text with a copy button
/// (the required manual path, spec §12 item (i)) and as a QR. The code is
/// the ONLY channel `ephPubN` travels — it never touches the server
/// (amendment (c)). Every failure path discards the adopted identity and
/// minted keys (I1 abort hygiene, falsification 18).
class LinkThisDeviceScreen extends StatefulWidget {
  const LinkThisDeviceScreen({super.key, required this.controller});

  final LinkCeremonyController controller;

  @override
  State<LinkThisDeviceScreen> createState() => _LinkThisDeviceScreenState();
}

class _LinkThisDeviceScreenState extends State<LinkThisDeviceScreen> {
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStep);
    widget.controller.startNewDeviceFlow(platform: linkPlatformLabel());
  }

  /// Same exit as the primary side: `done` returns to the devices screen —
  /// which re-reads the list on the rebound socket ((lxviii) clause 1) — and
  /// the confirmation is a toast there. The pop is not an abort for `done`.
  void _onStep() {
    if (_popped || !mounted) return;
    if (widget.controller.newDeviceStep != NewDeviceLinkStep.done) return;
    _popped = true;
    // Delivered from a controller notification, possibly mid-build: never
    // navigate inside a build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showTopSnackBar(context, AppLocalizations.of(context).linkNewDone);
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStep);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // Amendment (lxvi) clause 3: the abort hangs off the POP, not the arrow,
    // so gesture/hardware/browser back take the same exit — a stage the user
    // walked away from must never stay approvable by the primary (I1).
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        final step = widget.controller.newDeviceStep;
        if (step != NewDeviceLinkStep.done &&
            step != NewDeviceLinkStep.aborted &&
            step != NewDeviceLinkStep.idle) {
          widget.controller.abortNewDevice('cancelled_locally');
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: GlassTopBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l10n.linkNewTitle,
            style: RpgTheme.bodyFont(
              fontSize: 16,
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => SingleChildScrollView(
            padding: EdgeInsets.only(
              top:
                  MediaQuery.paddingOf(context).top +
                  GlassTopBar.capsuleHeight +
                  16,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildStep(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;

    switch (controller.newDeviceStep) {
      case NewDeviceLinkStep.idle:
      case NewDeviceLinkStep.opening:
        return const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ];
      case NewDeviceLinkStep.showCode:
      case NewDeviceLinkStep.showSas:
        final code = controller.oobCode ?? '';
        final sas = controller.newDeviceSas;
        return [
          Text(
            l10n.linkNewExplainer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // A QR quiet zone must be light for scanability on every
                // theme — functional, not styling (playbook literal-color
                // exception).
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              // The QR is the deep-link form: a phone camera opens the app
              // at `/link#<code>`; the fragment never leaves the browser.
              // The semantics label carries the same payload so a screen
              // reader (and the widget test) sees exactly what the camera
              // will.
              child: Builder(
                builder: (_) {
                  final qrPayload =
                      LinkOobCode.tryParse(
                        code,
                      )?.toDeepLink(linkDeepLinkOrigin()) ??
                      code;
                  return QrImageView(
                    data: qrPayload,
                    semanticsLabel: 'link qr $qrPayload',
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Semantics(
              label: 'link code',
              child: SelectableText(
                code,
                key: const Key('link-oob-code'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: l10n.linkNewCopy,
            button: true,
            child: OutlinedButton.icon(
              key: const Key('link-copy-code'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  showTopSnackBar(context, l10n.linkNewCopied);
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(l10n.linkNewCopy),
            ),
          ),
          const SizedBox(height: 24),
          if (sas == null)
            Text(
              l10n.linkNewWaitingHello,
              key: const Key('link-new-waiting-hello'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              l10n.linkSasHeading,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.linkSasExplainer,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'security code $sas',
              child: Container(
                key: const Key('link-new-sas-code'),
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Text(
                  sas,
                  textAlign: TextAlign.center,
                  style: RpgTheme.bodyFont(
                    fontSize: 40,
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ).copyWith(letterSpacing: 6),
                ),
              ),
            ),
          ],
        ];
      case NewDeviceLinkStep.completing:
      case NewDeviceLinkStep.rebinding:
        return [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          Text(
            controller.newDeviceStep == NewDeviceLinkStep.rebinding
                ? l10n.linkNewRebinding
                : l10n.linkNewCompleting,
            key: const Key('link-new-progress'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ];
      case NewDeviceLinkStep.done:
        return [
          Icon(Icons.check_circle_outline, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            l10n.linkNewDone,
            key: const Key('link-new-done'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ];
      case NewDeviceLinkStep.aborted:
        final reason = controller.newDeviceError;
        final reasonLabel = switch (reason) {
          'expired' => l10n.linkAbortReasonExpired,
          'cancelled' => l10n.linkAbortReasonCancelled,
          'bad_mac' ||
          'malformed' ||
          'blob_user_mismatch' => l10n.linkAbortReasonBadBlob,
          _ => '${l10n.linkNewAborted} ($reason)',
        };
        return [
          Icon(Icons.error_outline, size: 48, color: colors.error),
          const SizedBox(height: 16),
          Text(
            reasonLabel,
            key: const Key('link-new-error'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: l10n.linkNewRetry,
            button: true,
            child: OutlinedButton(
              key: const Key('link-new-retry'),
              onPressed: () =>
                  controller.startNewDeviceFlow(platform: linkPlatformLabel()),
              child: Text(l10n.linkNewRetry),
            ),
          ),
        ];
    }
  }
}
