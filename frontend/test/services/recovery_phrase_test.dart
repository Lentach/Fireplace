import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/services/recovery_phrase.dart';

/// Recovery phrase generation and local checking (multi-device spec §6.2.1).
///
/// The checksum matters for a practical reason, not a ceremonial one: the
/// server locks the phrase out after five failed presentations, so a typo that
/// reaches it costs the user one of very few chances to get their account back.
void main() {
  group('generate', () {
    test('produces twelve words', () {
      expect(RecoveryPhrase.generate().length, 12);
    });

    test('produces a phrase that validates', () {
      final phrase = RecoveryPhrase.generate().join(' ');
      expect(RecoveryPhrase.isValid(phrase), isTrue);
    });

    test('does not repeat itself', () {
      // 128 bits of entropy: a collision here means the generator is broken,
      // not that the test was unlucky.
      final first = RecoveryPhrase.generate().join(' ');
      final second = RecoveryPhrase.generate().join(' ');
      expect(first, isNot(second));
    });
  });

  group('isValid', () {
    test('accepts a known-good BIP39 phrase', () {
      expect(
        RecoveryPhrase.isValid(
          'legal winner thank year wave sausage worth useful legal winner '
          'thank yellow',
        ),
        isTrue,
      );
    });

    test('tolerates casing and sloppy whitespace', () {
      expect(
        RecoveryPhrase.isValid(
          '  LEGAL winner  thank year wave sausage worth useful legal winner '
          'thank YELLOW ',
        ),
        isTrue,
      );
    });

    test('rejects a phrase whose checksum does not hold', () {
      // Same wordlist, last word swapped — the shape a typo takes.
      expect(
        RecoveryPhrase.isValid(
          'legal winner thank year wave sausage worth useful legal winner '
          'thank zebra',
        ),
        isFalse,
      );
    });

    test('rejects a word that is not in the list', () {
      expect(
        RecoveryPhrase.isValid(
          'legal winner thank year wave sausage worth useful legal winner '
          'thank fireplace',
        ),
        isFalse,
      );
    });
    test('rejects the wrong number of words', () {
      expect(RecoveryPhrase.isValid('legal winner thank year'), isFalse);
      expect(
        RecoveryPhrase.isValid(
          'legal winner thank year wave sausage worth useful legal winner '
          'thank yellow yellow',
        ),
        isFalse,
      );
    });

    test('rejects empty input', () {
      expect(RecoveryPhrase.isValid(''), isFalse);
      expect(RecoveryPhrase.isValid('   '), isFalse);
    });
  });
}
