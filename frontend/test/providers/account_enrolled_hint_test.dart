import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/account_enrolled_hint.dart';
import 'package:fireplace/services/encryption_service.dart';

/// (lxxvi) clause 1, the WRITE half: every explicit
/// `ownKeyBundleStatus.linkingEnabled` observation persists the cleartext
/// `account_enrolled_hint_<uid>` prefs bool the lock screen reads (the erase
/// panel cannot read E2E state — on web the store is wrapped while locked).
///
/// Falsification F1: with the write site removed, `enrolment persists TRUE`
/// fails on its `prefs.getBool(...), isTrue` assertion — the hint is simply
/// never written and the enrolled erase copy can never render.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<EncryptionProvider> initWith(Map<String, dynamic> payload) async {
    final provider = EncryptionProvider(service: EncryptionService());
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus(payload);
      }
    });
    await provider.initializeE2E(7);
    // The hint write is fire-and-forget off the status handler.
    await Future<void>.delayed(Duration.zero);
    return provider;
  }

  test('an explicit linkingEnabled TRUE persists the enrolment hint', () async {
    await initWith({'exists': false, 'linkingEnabled': true});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('account_enrolled_hint_7'), isTrue);
    expect(await AccountEnrolledHint.read(userId: 7), isTrue);
  });

  test('an explicit FALSE overwrites a stale TRUE — un-enrolment is observed '
      'too', () async {
    SharedPreferences.setMockInitialValues({'account_enrolled_hint_7': true});

    await initWith({'exists': false, 'linkingEnabled': false});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('account_enrolled_hint_7'), isFalse);
  });

  test('an ABSENT linkingEnabled writes NOTHING: the fail-closed parse '
      'default (absent => true) guards key minting and must not claim '
      'enrolment for copy', () async {
    await initWith({'exists': false});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('account_enrolled_hint_7'), isNull);
  });
}
