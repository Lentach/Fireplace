import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_dialog.dart';
import 'package:fireplace/widgets/identity_damaged_banner.dart';
import 'package:fireplace/widgets/own_identity_replaced_banner.dart';
import 'package:fireplace/widgets/peer_identity_changed_row.dart';
import 'package:fireplace/widgets/peer_identity_fingerprint_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Every surface here is a warning about broken or suspicious cryptography.
/// Showing one when nothing is wrong is worse than not shipping it: a
/// permanent red "your keys are damaged" bar trains the dismissal reflex the
/// surface exists to defeat. So the off-state is tested first and hardest.
/// The damaged banner carries NO destructive action since amendment (lxxi) —
/// that absence is asserted, not assumed.
class _FakeEncryption extends EncryptionProvider {
  _FakeEncryption({
    this.damaged = false,
    this.changedPeers = const <int>{},
    this.peerFingerprint,
    this.offeredFingerprint,
    this.offeredKey,
    this.offeredWasServed = false,
    this.ownFingerprint,
    this.replacedAt,
  });

  bool damaged;
  Set<int> changedPeers;
  String? peerFingerprint;

  /// The key the ceremony would PIN, as the real provider resolves it: from a
  /// stored candidate, or — for a peer whose recovery path fail-closed before
  /// one could be recorded — from a fresh server fetch ((xlvii) clause 3).
  String? offeredFingerprint;
  String? offeredKey;
  bool offeredWasServed;

  String? ownFingerprint;
  final List<int> acknowledged = <int>[];

  /// What each acknowledgement was asked to pin. The dialog MUST hand back the
  /// key it displayed ((xlvii) clause 2) — pinning anything else is the defect
  /// this records.
  final List<String?> adoptedKeys = <String?>[];
  String? replacedAt;
  int dismissCalls = 0;

  @override
  bool get identityIncomplete => damaged;

  @override
  Set<int> get peersWithChangedIdentity => changedPeers;

  @override
  String? get ownIdentityReplacedAt => replacedAt;

  @override
  Future<void> dismissOwnIdentityReplaced() async {
    dismissCalls++;
    replacedAt = null;
    notifyListeners();
  }

  @override
  Future<String?> getPeerIdentityFingerprint(int peerId) async =>
      peerFingerprint;

  @override
  Future<String?> getIdentityFingerprint() async => ownFingerprint;

  @override
  Future<PeerIdentityVerification> loadPeerIdentityVerification(
    int peerId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // An offer exists only while a warning stands, matching the real provider:
    // a proactive open has nothing to adopt.
    final standing = changedPeers.contains(peerId);
    return PeerIdentityVerification(
      pinnedFingerprint: peerFingerprint,
      offeredFingerprint: standing ? offeredFingerprint : null,
      offeredIdentityBase64: standing ? offeredKey : null,
      offeredWasServed: standing && offeredWasServed,
    );
  }

  /// When true, the acknowledgement REFUSES — the compare-and-swap found the
  /// candidate had moved since the fingerprint was displayed.
  bool refuseAcknowledge = false;

  @override
  Future<bool> acknowledgePeerIdentity(
    int peerId, {
    String? adoptIdentityBase64,
  }) async {
    acknowledged.add(peerId);
    adoptedKeys.add(adoptIdentityBase64);
    if (refuseAcknowledge) return false;
    changedPeers = changedPeers.where((id) => id != peerId).toSet();
    notifyListeners();
    return true;
  }
}

class _FakeAuthProvider extends AuthProvider {
  @override
  UserModel? get currentUser => UserModel(id: 7, username: 'qa', tag: '0001');
}

class _FakeConnectionProvider extends ConnectionProvider {
  @override
  int? get currentUserId => 7;
}

Widget _host(EncryptionProvider encryption, Widget child) {
  // The auth and connection fakes exist so the DevicesScreen the (lxvii) link
  // action pushes can build; the banners themselves read only encryption.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
      ChangeNotifierProvider<ConnectionProvider>(
        create: (_) => _FakeConnectionProvider(),
      ),
      ChangeNotifierProvider<EncryptionProvider>.value(value: encryption),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('IdentityDamagedBanner', () {
    testWidgets('renders NOTHING when the identity is healthy', (tester) async {
      final encryption = _FakeEncryption();
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));

      expect(find.byType(Material), findsOneWidget); // the Scaffold's own
      expect(find.byIcon(Icons.gpp_bad_outlined), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(
        tester.widget<SizedBox>(
          find.descendant(
            of: find.byType(IdentityDamagedBanner),
            matching: find.byType(SizedBox),
          ),
        ),
        isA<SizedBox>(),
        reason: 'a healthy device must never see a destructive key action',
      );
    });

    testWidgets('warns and leads with the LINK when the identity is damaged', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.byIcon(Icons.gpp_bad_outlined), findsOneWidget);
      // (lxvii) clause 1: a keyless install of an enrolled account is, first,
      // a second device. The only action is the non-destructive §5.1 link.
      expect(find.byKey(const Key('identity-damaged-link')), findsOneWidget);
      expect(find.text(l10n.devicesLinkThisDevice), findsOneWidget);
      expect(
        find.byKey(const Key('identity-damaged-start-fresh')),
        findsNothing,
        reason: '(lxxi): there is no start-fresh; it minted an identity no '
            'peer trusts',
      );
    });

    testWidgets('the paragraph is COLLAPSED, while the action stays visible', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // The title says what happened; the four-sentence explanation does not
      // occupy persistent chrome. A warning nobody finishes reading trains the
      // dismissal reflex this whole surface exists to avoid.
      expect(find.text(l10n.identityDamagedTitle), findsOneWidget);
      expect(
        find.text(l10n.identityDamagedBody),
        findsNothing,
        reason: 'the body must not be rendered until asked for',
      );
      // The safe way out of a damaged identity must never hide behind a
      // disclosure control.
      expect(find.byKey(const Key('identity-damaged-link')), findsOneWidget);
    });

    testWidgets('the link action routes to the devices screen', (tester) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));

      // The push is what matters; DevicesScreen itself needs the connection
      // and auth providers, so it is asserted by route, not by build.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
      await tester.tap(find.byKey(const Key('identity-damaged-link')));
      await tester.pump();
      expect(
        navigator.canPop(),
        isTrue,
        reason: 'the link action must push the §5.1 host screen',
      );
    });

    testWidgets('the explanation is one tap away and fully readable', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.text(l10n.identityDamagedBody), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);

      // And it collapses again.
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      expect(find.text(l10n.identityDamagedBody), findsNothing);
    });

    testWidgets('a screen reader gets the detail even while collapsed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Collapsing is a DENSITY decision, never a way to hide a warning from
      // someone who cannot see the chevron.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(l10n.identityDamagedBody))),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the banner carries no SafeArea of its own', (tester) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));

      // These banners are SIBLINGS in the shell's Column, and a sibling
      // SafeArea does not consume the inset for its neighbours — each one
      // applies the FULL top inset. Three self-wrapping banners produced two
      // phantom status-bar gaps between the red blocks. The shell wraps the
      // stack once instead, so a SafeArea reappearing here is a regression.
      expect(
        find.descendant(
          of: find.byType(IdentityDamagedBanner),
          matching: find.byType(SafeArea),
        ),
        findsNothing,
      );
    });

    testWidgets('no destructive action exists, collapsed or expanded', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      // (lxxi): the disclosure used to hide "Start fresh". The only button on
      // this banner, in either state, is the link; the copy no longer
      // suggests making new keys either.
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byKey(const Key('identity-damaged-link')), findsOneWidget);
      expect(find.byKey(const Key('identity-damaged-start-fresh')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        l10n.identityDamagedBody.toLowerCase(),
        isNot(contains('start fresh')),
      );
    });
  });

  group('OwnIdentityReplacedBanner', () {
    testWidgets('renders NOTHING when no replacement is pending', (
      tester,
    ) async {
      final encryption = _FakeEncryption();
      await tester.pumpWidget(
        _host(encryption, const OwnIdentityReplacedBanner()),
      );

      expect(find.byIcon(Icons.phonelink_lock_outlined), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('warns while a replacement is pending and dismiss clears it', (
      tester,
    ) async {
      final encryption = _FakeEncryption(
        replacedAt: '2026-08-17T12:00:00.000Z',
      );
      await tester.pumpWidget(
        _host(encryption, const OwnIdentityReplacedBanner()),
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.ownIdentityReplacedTitle), findsOneWidget);
      expect(find.byIcon(Icons.phonelink_lock_outlined), findsOneWidget);

      await tester.tap(find.text(l10n.ownIdentityReplacedDismissAction));
      await tester.pumpAndSettle();
      expect(encryption.dismissCalls, 1);
      expect(
        find.text(l10n.ownIdentityReplacedTitle),
        findsNothing,
        reason: 'dismissal is the only thing that clears the alarm',
      );
    });
  });

  group('PeerIdentityChangedRow', () {
    testWidgets('tap opens the fingerprint verify dialog', (tester) async {
      final encryption = _FakeEncryption(
        changedPeers: {7},
        peerFingerprint: '0123 4567 89ab cdef',
        offeredFingerprint: 'aaaa bbbb cccc dddd',
        offeredKey: 'T0ZGRVJFRA==',
        ownFingerprint: 'fedc ba98 7654 3210',
      );
      await tester.pumpWidget(
        _host(
          encryption,
          const PeerIdentityChangedRow(peerId: 7, peerName: 'bob'),
        ),
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.peerIdentityChangedTimelineRow('bob')),
        findsOneWidget,
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(GlassDialog), findsOneWidget);

      // The verify door still clears the warning exactly once from here.
      await tester.tap(find.text(l10n.peerIdentityMarkVerifiedAction));
      await tester.pumpAndSettle();
      expect(encryption.acknowledged, [7]);
    });
  });

  group('showPeerIdentityFingerprintDialog', () {
    /// Opens the dialog the way the peer's Safety section does — with no
    /// standing warning. This is the door that catches a FIRST-CONTACT
    /// substitution, which produces no key change to warn about.
    Widget proactiveHost(EncryptionProvider encryption) => _host(
      encryption,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showPeerIdentityFingerprintDialog(
            context: context,
            peerId: 7,
            peerName: 'bob',
          ),
          child: const Text('open'),
        ),
      ),
    );

    testWidgets('shows fingerprints with no warning standing, and offers no '
        'acknowledge action', (tester) async {
      final encryption = _FakeEncryption(
        peerFingerprint: '0123 4567 89ab cdef',
        ownFingerprint: 'fedc ba98 7654 3210',
      );
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.byType(GlassDialog), findsOneWidget);
      expect(find.text('0123 4567 89ab cdef'), findsOneWidget);
      // Nothing to acknowledge: offering it would train the habit of clearing
      // a warning that was never raised.
      expect(find.text(l10n.peerIdentityMarkVerifiedAction), findsNothing);
      expect(encryption.acknowledged, isEmpty);
    });

    testWidgets('verify names a missing stored peer key', (tester) async {
      final encryption = _FakeEncryption(ownFingerprint: 'fedc ba98 7654 3210');
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.peerIdentityFingerprintNoStoredKey),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('acknowledging a standing warning clears it exactly once', (
      tester,
    ) async {
      final encryption = _FakeEncryption(
        changedPeers: {7},
        peerFingerprint: '0123 4567 89ab cdef',
        offeredFingerprint: 'aaaa bbbb cccc dddd',
        offeredKey: 'T0ZGRVJFRA==',
        ownFingerprint: 'fedc ba98 7654 3210',
      );
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.peerIdentityMarkVerifiedAction));
      await tester.pumpAndSettle();

      expect(encryption.acknowledged, [7]);
      expect(encryption.peersWithChangedIdentity, isEmpty);
      expect(find.byType(GlassDialog), findsNothing, reason: 'dialog closes');
    });

    /// (xlvii) clause 2. The ceremony used to display the PINNED fingerprint
    /// while confirming promoted a different, never-shown candidate — so for
    /// any real rotation the number on screen could not match what the peer
    /// read out, and confirming pinned bytes the user had never compared.
    testWidgets('shows the offered key and pins exactly what it showed', (
      tester,
    ) async {
      final encryption = _FakeEncryption(
        changedPeers: {7},
        peerFingerprint: '0123 4567 89ab cdef',
        offeredFingerprint: 'aaaa bbbb cccc dddd',
        offeredKey: 'T0ZGRVJFRA==',
        ownFingerprint: 'fedc ba98 7654 3210',
      );
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // The key under consideration is on screen and labelled as the new one.
      expect(find.text('aaaa bbbb cccc dddd'), findsOneWidget);
      expect(
        find.text(l10n.peerIdentityFingerprintNewLabel('bob')),
        findsOneWidget,
      );
      // The pin is still shown, but only as context for what changed.
      expect(find.text('0123 4567 89ab cdef'), findsOneWidget);
      expect(
        find.text(l10n.peerIdentityFingerprintPreviousLabel),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.peerIdentityMarkVerifiedAction));
      await tester.pumpAndSettle();

      // The whole point: what was verified is what was pinned.
      expect(encryption.adoptedKeys, ['T0ZGRVJFRA==']);
    });

    /// (xlvii) clause 1, at the surface. With nothing to adopt there must be no
    /// confirm action at all: the old button called an acknowledgement that
    /// dropped the warning FIRST and then found nothing to promote, destroying
    /// the only persisted notice of a real event and repairing nothing.
    testWidgets('offers no confirm action when there is nothing to pin', (
      tester,
    ) async {
      final encryption = _FakeEncryption(
        changedPeers: {7},
        peerFingerprint: '0123 4567 89ab cdef',
        ownFingerprint: 'fedc ba98 7654 3210',
      );
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.peerIdentityMarkVerifiedAction), findsNothing);
      expect(
        find.text(l10n.peerIdentityFingerprintOfferUnavailable('bob')),
        findsOneWidget,
        reason: 'the user is told why there is nothing to confirm',
      );

      // The warning MUST still be standing.
      expect(encryption.peersWithChangedIdentity, {7});
      expect(encryption.acknowledged, isEmpty);
    });

    /// A served key has not been corroborated by any message that decrypted, so
    /// the out-of-band comparison is the only check there is. Say so.
    testWidgets('names a freshly served key as uncorroborated', (tester) async {
      final encryption = _FakeEncryption(
        changedPeers: {7},
        peerFingerprint: '0123 4567 89ab cdef',
        offeredFingerprint: 'aaaa bbbb cccc dddd',
        offeredKey: 'T0ZGRVJFRA==',
        offeredWasServed: true,
        ownFingerprint: 'fedc ba98 7654 3210',
      );
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.peerIdentityFingerprintServedNotice('bob')),
        findsOneWidget,
      );
    });

    /// A refused confirmation must NOT close the dialog. The compare-and-swap
    /// refuses when the candidate moved since the fingerprint was displayed, and
    /// closing on refusal would drop the user back to a standing warning that
    /// silently did not clear, with no hint that what they compared was stale.
    testWidgets('a refused confirmation stays open and says why', (
      tester,
    ) async {
      final encryption = _FakeEncryption(
        changedPeers: {7},
        peerFingerprint: '0123 4567 89ab cdef',
        offeredFingerprint: 'aaaa bbbb cccc dddd',
        offeredKey: 'T0ZGRVJFRA==',
        ownFingerprint: 'fedc ba98 7654 3210',
      )..refuseAcknowledge = true;
      await tester.pumpWidget(proactiveHost(encryption));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.peerIdentityMarkVerifiedAction));
      await tester.pumpAndSettle();

      expect(
        find.byType(GlassDialog),
        findsOneWidget,
        reason: 'the dialog must stay open so the ceremony can be re-run',
      );
      expect(
        find.text(l10n.peerIdentityFingerprintOfferChanged('bob')),
        findsOneWidget,
        reason: 'and it must say that nothing was confirmed, and why',
      );
      expect(encryption.peersWithChangedIdentity, {
        7,
      }, reason: 'the warning stands');
    });
  });
}
