import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/chat_auto_scroll.dart';

void main() {
  group('shouldAutoScrollOnNewMessages', () {
    // Truth table of the auto-scroll contract. Each row names the observable
    // behavior it defends; together they kill a flipped OR->AND, a dropped
    // `newOwnMessages > 0` term, a dropped `wasNearBottom` term, and a dropped
    // `!userHasScrolledChat` term.
    final cases =
        <({String name, int own, bool near, bool scrolled, bool expected})>[
      // Fix B: an own send (text, emote panel, media) MUST scroll to the newest
      // message even when the user had scrolled up and away from the bottom.
      (
        name: 'own send forces scroll despite scrolled away from bottom',
        own: 1,
        near: false,
        scrolled: true,
        expected: true,
      ),
      (
        name: 'several own sends still force scroll',
        own: 3,
        near: false,
        scrolled: true,
        expected: true,
      ),
      // Peer messages: scroll only when the user is near the bottom and has not
      // deliberately scrolled away.
      (
        name: 'peer message near bottom and not scrolled -> scroll',
        own: 0,
        near: true,
        scrolled: false,
        expected: true,
      ),
      (
        name: 'peer message away from bottom -> badge, no scroll',
        own: 0,
        near: false,
        scrolled: false,
        expected: false,
      ),
      (
        name: 'peer message near bottom but scrolled away -> no scroll',
        own: 0,
        near: true,
        scrolled: true,
        expected: false,
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        expect(
          shouldAutoScrollOnNewMessages(
            newOwnMessages: c.own,
            wasNearBottom: c.near,
            userHasScrolledChat: c.scrolled,
          ),
          c.expected,
        );
      });
    }
  });
}
