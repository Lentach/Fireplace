import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/invitation_state.dart';
import '../../models/user_model.dart';
import '../../theme/rpg_theme.dart';
import '../glass/glass_surface.dart';
import '../hex_avatar.dart';
import 'invitation_status_pill.dart';

enum InvitationRowState {
  inbound,
  outbound,
  acting,
  acceptedReady,
  acceptedNeedsChat,
}

/// One opaque relationship row for all invitation lifecycle states.
class InvitationRow extends StatelessWidget {
  final UserModel peer;
  final InvitationRowState state;
  final InvitationAction? actingAction;
  final bool retrying;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onOpenChat;
  final VoidCallback? onDone;
  final VoidCallback? onCreateChat;

  const InvitationRow({
    super.key,
    required this.peer,
    required this.state,
    this.actingAction,
    this.retrying = false,
    this.onAccept,
    this.onDecline,
    this.onOpenChat,
    this.onDone,
    this.onCreateChat,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Semantics(
      container: true,
      label: _semanticLabel(l10n),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(16),
        // Opaque content surface (SPEC §1). `blur: false` alone still paints the
        // translucent `GlassTheme.fill`; `forceOpaque` is what selects `opaqueFill`.
        forceOpaque: true,
        shadow: false,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HexAvatar(
                  size: 44,
                  displayName: peer.username,
                  imageUrl: peer.profilePictureUrl,
                  surface: colors.convItemBg,
                  borderColor: colors.convItemBorder,
                  initialsStyle: RpgTheme.bodyFont(
                    fontSize: 44 * 0.34,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    peer.displayHandle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: KeyedSubtree(
                key: ValueKey(state),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _stateContent(context, l10n, colors),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _semanticLabel(AppLocalizations l10n) => switch (state) {
    InvitationRowState.inbound || InvitationRowState.acting =>
      l10n.invitationSemanticIncoming(peer.displayHandle),
    InvitationRowState.outbound => l10n.invitationSemanticOutgoing(
      peer.displayHandle,
    ),
    InvitationRowState.acceptedReady => l10n.invitationSemanticAcceptedReady(
      peer.displayHandle,
    ),
    InvitationRowState.acceptedNeedsChat =>
      l10n.invitationSemanticAcceptedNotReady(peer.displayHandle),
  };

  Widget _stateContent(
    BuildContext context,
    AppLocalizations l10n,
    FireplaceColors colors,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (state) {
      InvitationRowState.inbound || InvitationRowState.acting => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.invitationWantsToConnect,
            style: RpgTheme.bodyFont(fontSize: 12, color: colors.mutedText),
          ),
          const SizedBox(height: 10),
          _incomingActions(context, l10n),
        ],
      ),
      InvitationRowState.outbound => Row(
        children: [
          Expanded(
            child: Text(
              l10n.invitationWaitingForResponse,
              style: RpgTheme.bodyFont(fontSize: 12, color: colors.mutedText),
            ),
          ),
          const SizedBox(width: 12),
          InvitationStatusPill(
            label: l10n.invitationStatusPending,
            kind: InvitationStatusPillKind.pending,
          ),
        ],
      ),
      InvitationRowState.acceptedReady => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.invitationAccepted,
                  style: RpgTheme.bodyFont(
                    fontSize: 12,
                    color: colors.mutedText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InvitationStatusPill(
                label: l10n.invitationChatReady,
                kind: InvitationStatusPillKind.ready,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _acceptedReadyActions(context, l10n),
        ],
      ),
      InvitationRowState.acceptedNeedsChat => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.invitationAccepted,
            style: RpgTheme.bodyFont(fontSize: 12, color: colors.mutedText),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.invitationChatNeedsRetry,
            style: RpgTheme.bodyFont(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _acceptedNeedsChatActions(context, l10n),
        ],
      ),
    };
  }

  /// The app-wide `ElevatedButton` padding is `vertical: 16`, tuned for standalone
  /// form buttons. In a list row that pushes each row past 150 px and the inbox
  /// scans as a settings page rather than the compact relationship inbox the design
  /// calls for. Only the padding is overridden; colour still comes from the theme.
  static const ButtonStyle _denseAction = ButtonStyle(
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
  );

  Widget _incomingActions(BuildContext context, AppLocalizations l10n) {
    final acting = state == InvitationRowState.acting;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: acting ? null : onAccept,
            style: _denseAction,
            child: _buttonLabel(
              l10n.accept,
              showProgress: acting && actingAction == InvitationAction.accept,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: acting ? null : onDecline,
          style: TextButton.styleFrom(
            foregroundColor: FireplaceColors.of(context).mutedText,
          ),
          child: _buttonLabel(
            l10n.invitationDecline,
            showProgress: acting && actingAction == InvitationAction.decline,
          ),
        ),
      ],
    );
  }

  Widget _acceptedReadyActions(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: onOpenChat,
            style: _denseAction,
            child: Text(l10n.invitationOpenChat),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onDone,
          style: TextButton.styleFrom(
            foregroundColor: FireplaceColors.of(context).mutedText,
          ),
          child: Text(l10n.invitationDone),
        ),
      ],
    );
  }

  Widget _acceptedNeedsChatActions(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: retrying ? null : onCreateChat,
            style: _denseAction,
            child: _buttonLabel(
              l10n.invitationCreateChat,
              showProgress: retrying,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onDone,
          style: TextButton.styleFrom(
            foregroundColor: FireplaceColors.of(context).mutedText,
          ),
          child: Text(l10n.invitationDone),
        ),
      ],
    );
  }

  Widget _buttonLabel(String label, {required bool showProgress}) {
    if (!showProgress) return Text(label);
    return const SizedBox(
      key: Key('invitation-action-progress'),
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
