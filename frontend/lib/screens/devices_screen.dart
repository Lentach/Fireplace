import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/encryption_provider.dart';
import '../services/device_link/link_ceremony_controller.dart';
import '../services/device_list/device_list_canonical.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_top_bar.dart';
import 'link_device_screen.dart';
import 'link_this_device_screen.dart';

/// The account's devices (multi-device spec §4/§5.1 — Phase 2 T3).
///
/// Owns the screen-scoped [LinkCeremonyController] and registers it as
/// ConnectionProvider's provisioning sink for its lifetime; the two link-flow
/// screens drive the same instance. The rendered list is ONLY the DAK-signed
/// canonical list, verified along the I7 chain against this device's own
/// identity — never the server's bare word.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  LinkCeremonyController? _controller;
  ConnectionProvider? _connection;

  /// (lxix): tombstones start collapsed; the toggle is per screen visit.
  bool _showRevoked = false;

  @override
  void initState() {
    super.initState();
    final connection = context.read<ConnectionProvider>();
    final encryption = context.read<EncryptionProvider>();
    final auth = context.read<AuthProvider>();
    final userId = connection.currentUserId ?? auth.currentUser?.id;
    if (userId == null) return;
    final controller = LinkCeremonyController(
      userId: userId,
      emit: connection.emit,
      identity: EncryptionServiceLinkGateway(encryption.encryptionService),
      adoptSession: auth.adoptProvisionedSession,
      // (lxv)/(lxvii): the ceremony may dispose stale material — (lxiv)
      // mismatch or a lock-refused identity. Read live at blob time — the
      // predicate is the provider's, not a snapshot.
      staleDisposalAuthorized: () => encryption.linkDisposesStaleMaterial,
      reconnect: (accessToken) async {
        // `immediate`: the reconnect debounce would defer this to a timer and
        // return at once, so the rebind's await would resolve BEFORE the
        // socket carries the new device — the same reason the §6.2 rebind
        // passes it. Rate-limited by the ceremony itself, not the cooldown.
        await connection.connect(
          userId,
          accessToken,
          AppConfig.baseUrl,
          immediate: true,
        );
      },
    );
    _controller = controller;
    _connection = connection;
    connection.registerProvisioningSink(controller);
    controller.refreshDeviceList();
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      _connection?.unregisterProvisioningSink(controller);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final encryption = context.watch<EncryptionProvider>();
    // The device-side (§5.1 N) CTA is the way out for EVERY shape of "this
    // install cannot do E2E duty here": no identity at all, (lxiv) stale
    // material stamped for a different device id, and (lxvii) an identity the
    // registration lock refused. None of these is served by the primary-side
    // flow, which such a device can never complete (it holds no DAK), so
    // offering it would dead-end the banner's promised recovery.
    final keyless = encryption.needsDeviceLink;

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
          l10n.devices,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: controller == null
          ? const SizedBox.shrink()
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) =>
                  _buildBody(context, controller, keyless: keyless),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LinkCeremonyController controller, {
    required bool keyless,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + GlassTopBar.capsuleHeight + 16,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
        left: 24,
        right: 24,
      ),
      children: [
        Text(
          l10n.devicesExplainer,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        ..._buildListSection(context, controller, keyless: keyless),
        const SizedBox(height: 24),
        ..._buildActions(context, controller, keyless: keyless),
      ],
    );
  }

  List<Widget> _buildListSection(
    BuildContext context,
    LinkCeremonyController controller, {
    required bool keyless,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // (lxviii) clause 3: the list verifies against this install's own
    // identity, so a keyless (or lock-refused) install cannot verify it and
    // the answer is `chainInvalid` by construction. Rendering that in red
    // directly above "this device holds no keys yet — link it" is two
    // explanations for one state, one of them alarming. The CTA is the whole
    // message; the list appears once the ceremony gives this install an
    // identity (clause 1's refresh).
    if (keyless) return const [];

    switch (controller.listState) {
      case DeviceListState.loading:
        return [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.devicesLoading,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ];
      case DeviceListState.notEnrolled:
        return [
          Text(
            l10n.devicesNotEnrolled,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ];
      case DeviceListState.chainInvalid:
        return [
          Text(
            l10n.devicesChainInvalid,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ];
      case DeviceListState.enrolled:
        final list = controller.verifiedList;
        if (list == null) return const [];
        // (lxix): revoked rows are permanent tombstones in the DAK-signed
        // bytes (§3 — ids are never reused, so a revoked device re-links as a
        // fresh id and its old row stays forever). Live devices lead; the
        // tombstones collapse behind one disclosure so twenty old revokes do
        // not bury the device that matters. Wire bytes untouched.
        final live = [
          for (final e in list.devices)
            if (e.revokedAtMs == null) e,
        ];
        final revoked = [
          for (final e in list.devices)
            if (e.revokedAtMs != null) e,
        ];
        Widget row(DeviceListEntry entry) => _DeviceRow(
          entry: entry,
          l10n: l10n,
          // Only the primary may revoke, and never itself (amendment
          // (xxi)) — the server enforces both; this just does not offer an
          // action guaranteed to be refused. The signed canonical list
          // carries NO primary flag (spec §3), so "primary" is read as
          // device 1, which is exactly true until §6.3 primary migration
          // ships. When it does, the flag has to reach the client (either
          // in the canonical list or beside it) and this condition must
          // move to it — a §6.2 reset already makes the primary a
          // freshly allocated id server-side.
          onRevoke:
              entry.revokedAtMs == null &&
                  entry.deviceId != 1 &&
                  entry.deviceId !=
                      context.read<EncryptionProvider>().ownDeviceId
              ? () => _confirmRevoke(context, controller, entry, l10n)
              : null,
          busy: controller.revokingDeviceId == entry.deviceId,
        );
        return [
          for (final entry in live) row(entry),
          if (revoked.isNotEmpty) ...[
            TextButton.icon(
              key: const Key('devices-revoked-toggle'),
              onPressed: () => setState(() => _showRevoked = !_showRevoked),
              icon: Icon(
                _showRevoked ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(l10n.devicesRevokedSection(revoked.length)),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            if (_showRevoked)
              for (final entry in revoked) row(entry),
          ],
          if (controller.revokeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.devicesRevokeFailed,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
        ];
    }
  }

  /// Revocation is destructive for the other device's session, so it is
  /// confirmed — and the copy states the two things users get wrong: the
  /// device is signed out, and its local history is NOT erased (spec §5.5
  /// logout semantics, remote wipe is a §1 non-goal).
  Future<void> _confirmRevoke(
    BuildContext context,
    LinkCeremonyController controller,
    DeviceListEntry entry,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.devicesRevokeTitle),
        content: Text(l10n.devicesRevokeExplainer),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          TextButton(
            key: const Key('devices-revoke-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.devicesRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // (lxix): the tombstone is the user's confirmation that the revoke
      // took — open the section so the row lands where they can see it,
      // instead of vanishing behind a collapsed disclosure.
      if (mounted) setState(() => _showRevoked = true);
      await controller.revokeDevice(entry.deviceId);
    }
  }

  List<Widget> _buildActions(
    BuildContext context,
    LinkCeremonyController controller, {
    required bool keyless,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final actions = <Widget>[];

    if (keyless) {
      // The new-device flow (N): this install holds no identity — the ONLY
      // way it gets one is the §5.1 ceremony.
      actions.addAll([
        Text(
          l10n.devicesThisDeviceKeyless,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: l10n.devicesLinkThisDevice,
          button: true,
          child: FilledButton(
            key: const Key('devices-link-this-device'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LinkThisDeviceScreen(controller: controller),
                ),
              );
            },
            child: Text(l10n.devicesLinkThisDevice),
          ),
        ),
      ]);
      return actions;
    }

    if (controller.listState == DeviceListState.notEnrolled) {
      actions.add(
        Semantics(
          label: l10n.devicesEnableLinking,
          button: true,
          child: FilledButton(
            key: const Key('devices-enable-linking'),
            onPressed: controller.enrolling
                ? null
                : () => controller.enableLinking(platform: linkPlatformLabel()),
            child: controller.enrolling
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.devicesEnableLinking),
          ),
        ),
      );
    } else if (controller.listState == DeviceListState.enrolled) {
      // (lxviii) clause 2: the primary-side flow needs the DAK, and only the
      // primary holds it (§5.5). A linked device is told where linking
      // happens instead of being walked into `linkNoDak` after typing a code.
      // `null` = not resolved yet: offer nothing rather than the wrong thing.
      switch (controller.holdsDak) {
        case true:
          actions.add(
            Semantics(
              label: l10n.devicesLinkADevice,
              button: true,
              child: FilledButton(
                key: const Key('devices-link-a-device'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LinkDeviceScreen(controller: controller),
                    ),
                  );
                },
                child: Text(l10n.devicesLinkADevice),
              ),
            ),
          );
        case false:
          actions.add(
            Text(
              l10n.devicesLinkedDeviceNote,
              key: const Key('devices-linked-device-note'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          );
        case null:
          break;
      }
    }

    final enrollError = controller.enrollError;
    if (enrollError != null) {
      actions.addAll([
        const SizedBox(height: 12),
        Text(
          // `already_enrolled` is a DISTINCT state: another install of this
          // account holds the authority (first-write-wins, I2).
          enrollError == 'already_enrolled'
              ? l10n.devicesAlreadyEnrolled
              : l10n.devicesEnrollFailed,
          key: const Key('devices-enroll-error'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]);
    }
    return actions;
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.entry,
    required this.l10n,
    this.onRevoke,
    this.busy = false,
  });

  final DeviceListEntry entry;
  final AppLocalizations l10n;

  /// Null when this device may not be revoked from here: itself, the primary,
  /// or one already revoked (spec §12 amendment (xxi)).
  final VoidCallback? onRevoke;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final added = DateTime.fromMillisecondsSinceEpoch(entry.addedAtMs);
    final addedLabel =
        '${added.year}-${added.month.toString().padLeft(2, '0')}-'
        '${added.day.toString().padLeft(2, '0')}';
    final revoked = entry.revokedAtMs != null;

    return Semantics(
      label:
          'device ${entry.deviceId} ${entry.platform}'
          '${revoked ? ' ${l10n.devicesRevokedBadge}' : ''}',
      child: Container(
        key: Key('device-row-${entry.deviceId}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              entry.platform == 'web'
                  ? Icons.language
                  : Icons.smartphone_outlined,
              size: 20,
              color: revoked ? colors.onSurfaceVariant : colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.platform} · #${entry.deviceId}'
                    '${entry.deviceId == 1 ? ' · ${l10n.devicesPrimaryBadge}' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: revoked
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                      decoration: revoked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    revoked ? l10n.devicesRevokedBadge : addedLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (onRevoke != null)
              IconButton(
                key: Key('device-revoke-${entry.deviceId}'),
                icon: const Icon(Icons.link_off, size: 20),
                tooltip: l10n.devicesRevokeAction,
                onPressed: onRevoke,
              ),
          ],
        ),
      ),
    );
  }
}
