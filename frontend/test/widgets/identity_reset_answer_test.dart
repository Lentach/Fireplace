import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/l10n/app_localizations_en.dart';
import 'package:fireplace/l10n/app_localizations_pl.dart';
import 'package:fireplace/widgets/recovery_phrase_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every answer the reset ceremony can give must reach the user (§6.2).
///
/// Three of the five refuse to start anything, and they are exactly the ones a
/// genuine owner recovering lost keys runs into: a mistyped phrase that still
/// passes the local BIP39 checksum, the lockout after five of those, and the
/// cooldown that follows a cancel. Silence there looks like a dead button
/// while the account stays unreachable.
void main() {
  final AppLocalizations en = AppLocalizationsEn();
  final AppLocalizations pl = AppLocalizationsPl();

  const answers = <String>[
    'pending',
    'existing',
    'cooldown',
    'invalid_phrase',
    'locked',
  ];

  test('every server answer produces a sentence, in both languages', () {
    for (final status in answers) {
      expect(
        identityResetAnswerMessage(en, status),
        isNotNull,
        reason: '$status has no English copy',
      );
      expect(
        identityResetAnswerMessage(pl, status),
        isNotNull,
        reason: '$status has no Polish copy',
      );
    }
  });

  test('the answers are distinguishable, not one generic line', () {
    final messages = answers
        .map((status) => identityResetAnswerMessage(en, status))
        .toSet();

    expect(messages.length, answers.length);
  });

  test('no answer at all is reported as such, never as success', () {
    expect(identityResetAnswerMessage(en, null), en.identityResetNoAnswer);
    expect(identityResetAnswerIsRefusal(null), isTrue);
  });

  test('refusals are marked as refusals so they can be styled as errors', () {
    expect(identityResetAnswerIsRefusal('cooldown'), isTrue);
    expect(identityResetAnswerIsRefusal('invalid_phrase'), isTrue);
    expect(identityResetAnswerIsRefusal('locked'), isTrue);
    expect(identityResetAnswerIsRefusal('pending'), isFalse);
    expect(identityResetAnswerIsRefusal('existing'), isFalse);
  });

  test('the cooldown message names the way out', () {
    // A password thief can loop start+cancel and hold the cooldown open; the
    // owner's escape is to change the password and evict them, so the message
    // has to say so rather than leaving them stuck.
    expect(en.identityResetCooldown.toLowerCase(), contains('password'));
    expect(pl.identityResetCooldown.toLowerCase(), contains('hasło'));
  });

  test('an unknown future status says nothing rather than guessing', () {
    expect(identityResetAnswerMessage(en, 'something_new'), isNull);
  });
}
