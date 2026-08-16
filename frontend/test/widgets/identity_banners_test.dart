import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/identity_damaged_banner.dart';
import 'package:fireplace/widgets/peer_identity_fingerprint_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Both surfaces here are warnings about broken or suspicious cryptography,
/// and one of them offers a DESTRUCTIVE action. Showing either when nothing is
/// wrong is worse than not shipping them: a permanent red "your keys are
/// damaged" bar with a "start fresh" button would push healthy users into
/// wiping their own sessions. So the off-state is tested first and hardest.
class _FakeEncryption extends EncryptionProvider {
  _FakeEncryption({
    this.damaged = false,
    this.changedPeers = const <int>{},
    this.peerFingerprint,
    this.ownFingerprint,
  });

  bool damaged;
  Set<int> changedPeers;
  String? peerFingerprint;
  String? ownFingerprint;
  int recoverCalls = 0;
  final List<int> acknowledged = <int>[];
  bool recovering = false;

  @override
  bool get identityIncomplete => damaged;

  @override
  bool get identityRecoveryInFlight => recovering;

  @override
  Set<int> get peersWithChangedIdentity => changedPeers;

  @override
  Future<String?> getPeerIdentityFingerprint(int peerId) async =>
      peerFingerprint;

  @override
  Future<String?> getIdentityFingerprint() async => ownFingerprint;

  @override
  Future<void> recoverFromIncompleteIdentity() async {
    recoverCalls++;
  }

  @override
  Future<void> acknowledgePeerIdentity(int peerId) async {
    acknowledged.add(peerId);
    changedPeers = changedPeers.where((id) => id != peerId).toSet();
    notifyListeners();
  }
}

Widget _host(EncryptionProvider encryption, Widget child) {
  return ChangeNotifierProvider<EncryptionProvider>.value(
    value: encryption,
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

    testWidgets('warns and offers recovery when the identity is damaged', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));

      expect(find.byIcon(Icons.gpp_bad_outlined), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('the destructive action is disabled while it runs', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true)..recovering = true;
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));

      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(
        button.onPressed,
        isNull,
        reason:
            'a second tap during key generation would race a concurrent '
            'identity write against the same pre-key counter',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('recovery only runs after explicit confirmation', (
      tester,
    ) async {
      final encryption = _FakeEncryption(damaged: true);
      await tester.pumpWidget(_host(encryption, const IdentityDamagedBanner()));

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      // The dialog is up; nothing destructive has happened yet.
      expect(encryption.recoverCalls, 0);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(
        encryption.recoverCalls,
        0,
        reason: 'cancelling must never wipe keys',
      );

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.identityDamagedConfirmAction));
      await tester.pumpAndSettle();
      expect(encryption.recoverCalls, 1);
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
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('0123 4567 89ab cdef'), findsOneWidget);
      // Nothing to acknowledge: offering it would train the habit of clearing
      // a warning that was never raised.
      expect(find.text(l10n.peerIdentityMarkVerifiedAction), findsNothing);
      expect(encryption.acknowledged, isEmpty);
    });

    testWidgets('verify names a missing stored peer key', (tester) async {
      final encryption = _FakeEncryption(
        ownFingerprint: 'fedc ba98 7654 3210',
      );
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
      expect(find.byType(AlertDialog), findsNothing, reason: 'dialog closes');
    });
  });
}
