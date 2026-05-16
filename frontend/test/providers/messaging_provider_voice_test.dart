import 'dart:typed_data';

import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessagingProvider.sendVoiceMessage', () {
    late MessagingProvider provider;

    setUp(() {
      provider = MessagingProvider();
    });

    test('throws when not authenticated', () async {
      await expectLater(
        provider.sendVoiceMessage(
          recipientId: 2,
          duration: 1,
          localAudioBytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when no active conversation', () async {
      provider.setCurrentUserId(1);
      await expectLater(
        provider.sendVoiceMessage(
          recipientId: 2,
          duration: 1,
          localAudioBytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
