import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/devices_syncing_note.dart';
import 'package:fireplace/widgets/identity_damaged_banner.dart';
import 'package:fireplace/widgets/own_identity_replaced_banner.dart';
import 'package:fireplace/widgets/peer_identity_changed_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Multi-device spec §12 amendment (xvii): the own-device-skew note MUST NOT
/// reuse the identity-changed surface — no security colour, no icon, no sound.
///
/// The reason that is a rule and not a preference: this state fires when the
/// account's own devices have not finished syncing, which is benign and
/// COMMON. Dressing it as an attack teaches users that the red bar means
/// nothing, and the red bar is where [IdentityDamagedBanner] offers to wipe
/// their keys.
///
/// WHAT THIS TEST IS *NOT*. Asserting `find.byType(IdentityDamagedBanner)` is
/// `findsNothing` proves nothing at all here — the note never constructs those
/// widgets, so that assertion stays green even if the note were painted on the
/// error palette behind a lock icon. The load-bearing assertions are the ones
/// on COLOUR and on the absence of any [Icon]; the widget-absence checks are
/// kept only as a cheap backstop against someone wrapping a real alarm surface
/// in here later.
Widget _host(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: RpgTheme.themeDataLight,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('DevicesSyncingNote borrows nothing from the identity surface', () {
    testWidgets('its text is NOT on the error palette', (tester) async {
      await tester.pumpWidget(_host(const DevicesSyncingNote()));
      final colors = RpgTheme.themeDataLight.colorScheme;

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(DevicesSyncingNote),
          matching: find.byType(Text),
        ),
      );
      final colour = text.style?.color;

      expect(colour, isNotNull, reason: 'the note must set its own colour');
      // The three alarm surfaces all paint onErrorContainer text on an
      // errorContainer Material. Borrowing either token is the regression.
      expect(colour, isNot(colors.onErrorContainer));
      expect(colour, isNot(colors.errorContainer));
      expect(colour, isNot(colors.error));
      expect(colour, RpgTheme.textSecondaryLight);
    });

    testWidgets('carries no icon at all, least of all a security glyph', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const DevicesSyncingNote()));

      expect(
        find.descendant(
          of: find.byType(DevicesSyncingNote),
          matching: find.byType(Icon),
        ),
        findsNothing,
        reason:
            '(xvii): no icon — a glyph is what makes a note look like an alarm',
      );
      // Named explicitly so a future copy-paste from a sibling surface is loud.
      expect(find.byIcon(Icons.gpp_bad_outlined), findsNothing);
      expect(find.byIcon(Icons.phonelink_lock_outlined), findsNothing);
      expect(find.byIcon(Icons.key_outlined), findsNothing);
    });

    testWidgets('sits on no Material of its own — no coloured container', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const DevicesSyncingNote()));

      expect(
        find.descendant(
          of: find.byType(DevicesSyncingNote),
          matching: find.byType(Material),
        ),
        findsNothing,
        reason:
            'the three identity surfaces are each a Material on '
            'errorContainer; this note is bare inline text',
      );
    });

    testWidgets('shows the calm copy in en and in pl, and no alarm copy', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const DevicesSyncingNote()));
      var l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.devicesSyncingNote), findsOneWidget);
      expect(find.text(l10n.identityDamagedTitle), findsNothing);
      expect(find.text(l10n.ownIdentityReplacedTitle), findsNothing);

      await tester.pumpWidget(
        _host(const DevicesSyncingNote(), locale: const Locale('pl')),
      );
      await tester.pumpAndSettle();
      l10n = await AppLocalizations.delegate.load(const Locale('pl'));
      expect(
        find.text(l10n.devicesSyncingNote),
        findsOneWidget,
        reason: '(xvii) requires the calm note in en AND pl',
      );
      expect(find.text(l10n.identityDamagedTitle), findsNothing);
    });

    testWidgets('renders none of the three identity/takeover surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const DevicesSyncingNote()));

      // Cheap backstop only — see the file comment. These cannot catch a
      // styling regression, which is why they are last and not the point.
      expect(find.byType(IdentityDamagedBanner), findsNothing);
      expect(find.byType(OwnIdentityReplacedBanner), findsNothing);
      expect(find.byType(PeerIdentityChangedRow), findsNothing);
    });
  });
}
