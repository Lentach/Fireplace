import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/device_link/link_ceremony_controller.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_top_bar.dart';
import '../widgets/top_snackbar.dart';

/// The PRIMARY side of the §5.1 link ceremony (Phase 2 T3).
///
/// Manual paste is the REQUIRED out-of-band path (spec §12 item (i)): the
/// human carries the code from the new device's screen to this field. The
/// SAS is displayed large; the IK-bearing blob is built ONLY after Approve
/// (secrets-last, I3).
class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({
    super.key,
    required this.controller,
    this.initialCode,
  });

  final LinkCeremonyController controller;

  /// A code that arrived by QR deep link: the ceremony starts at once, the
  /// human skips straight to the SAS comparison. The field is still shown
  /// (prefilled) if the start fails, so a bad scan can be corrected by hand.
  final String? initialCode;

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final TextEditingController _code = TextEditingController();
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStep);
    final initial = widget.initialCode;
    if (initial != null) {
      _code.text = initial;
      // The controller notifies synchronously; starting inside the first
      // build would mark this route's AnimatedBuilder dirty mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.startPrimaryFlow(initial);
      });
    }
  }

  /// The ceremony's end is the DEVICES screen, not a checkmark waiting for a
  /// back tap: pop once on `done`, and let the devices screen confirm. The
  /// pop's `cancelPrimary` is idempotent for a finished ceremony.
  void _onStep() {
    if (_popped || !mounted) return;
    if (widget.controller.primaryStep != PrimaryLinkStep.done) return;
    _popped = true;
    // The toast lives on the root Overlay, which outlives this route.
    showTopSnackBar(context, AppLocalizations.of(context).linkPrimaryDone);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStep);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // Amendment (lxvi) clause 3: the cancel hangs off the POP, not the arrow,
    // so gesture/hardware/browser back take the same exit and never leave a
    // live stage behind. `cancelPrimary` is idempotent for a `done` ceremony.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.controller.cancelPrimary();
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
            l10n.linkPrimaryTitle,
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

    switch (controller.primaryStep) {
      case PrimaryLinkStep.idle:
        return [
          Text(
            l10n.linkPrimaryExplainer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Semantics(
            label: l10n.linkPrimaryCodeLabel,
            textField: true,
            child: TextField(
              key: const Key('link-code-field'),
              controller: _code,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: InputDecoration(
                labelText: l10n.linkPrimaryCodeLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: l10n.linkPrimaryContinue,
            button: true,
            child: FilledButton(
              key: const Key('link-code-continue'),
              onPressed: () => controller.startPrimaryFlow(_code.text),
              child: Text(l10n.linkPrimaryContinue),
            ),
          ),
        ];
      case PrimaryLinkStep.awaitingHelloAck:
      case PrimaryLinkStep.staging:
        return const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ];
      case PrimaryLinkStep.showSas:
        return [
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
          const SizedBox(height: 24),
          _SasCode(code: controller.primarySas ?? ''),
          const SizedBox(height: 32),
          Semantics(
            label: l10n.linkApprove,
            button: true,
            child: FilledButton(
              key: const Key('link-approve'),
              onPressed: controller.approvePrimary,
              child: Text(l10n.linkApprove),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: l10n.linkCancel,
            button: true,
            child: OutlinedButton(
              key: const Key('link-cancel'),
              onPressed: () {
                controller.cancelPrimary();
                Navigator.of(context).pop();
              },
              child: Text(l10n.linkCancel),
            ),
          ),
        ];
      case PrimaryLinkStep.waitingForDevice:
        return [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          Text(
            controller.primaryError == 'stale_version'
                ? l10n.linkStaleVersionRetry
                : l10n.linkWaitingForDevice,
            key: const Key('link-waiting'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ];
      case PrimaryLinkStep.done:
        return [
          Icon(Icons.check_circle_outline, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            l10n.linkPrimaryDone,
            key: const Key('link-primary-done'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ];
      case PrimaryLinkStep.failed:
        return [
          Icon(Icons.error_outline, size: 48, color: colors.error),
          const SizedBox(height: 16),
          Text(
            controller.primaryError == 'invalid_code'
                ? l10n.linkInvalidCode
                : controller.primaryError == 'no_dak'
                ? l10n.linkNoDak
                : '${l10n.linkFailed} (${controller.primaryError})',
            key: const Key('link-primary-error'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: l10n.linkNewRetry,
            button: true,
            child: OutlinedButton(
              key: const Key('link-primary-retry'),
              onPressed: () {
                controller.cancelPrimary();
              },
              child: Text(l10n.linkNewRetry),
            ),
          ),
        ];
    }
  }
}

/// Large 'XXX XXX' SAS rendering, shared look for both ceremony sides.
class _SasCode extends StatelessWidget {
  const _SasCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'security code $code',
      child: Container(
        key: const Key('link-sas-code'),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Text(
          code,
          textAlign: TextAlign.center,
          style: RpgTheme.bodyFont(
            fontSize: 40,
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ).copyWith(letterSpacing: 6),
        ),
      ),
    );
  }
}
