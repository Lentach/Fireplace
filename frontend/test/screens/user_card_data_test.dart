import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/screens/user_card_screen.dart';

void main() {
  UserCardVisualData cardFor(Map<String, dynamic> payload) {
    return UserCardVisualData.fromUser(
      UserModel.fromJson(payload),
      isSelf: false,
      hasConversation: true,
    );
  }

  test('uses compact no-avatar state when a profile has no photo', () {
    final card = cardFor({
      'id': 1,
      'username': 'alice',
      'tag': '0042',
      'profilePictureUrl': null,
      'profilePhotos': [],
    });

    expect(card.handle, 'alice#0042');
    expect(card.photos, isEmpty);
  });

  test('adapts legacy primary photo to a single stable card photo', () {
    final card = cardFor({
      'id': 1,
      'username': 'alice',
      'tag': '0042',
      'profilePictureUrl': 'https://media.example/avatar.jpg',
      'profilePhotos': [],
    });

    expect(card.photos, hasLength(1));
    expect(card.photos.single.url, 'https://media.example/avatar.jpg');
    expect(card.photos.single.semanticLabel, 'alice#0042');
  });

  test('keeps normalized gallery order and immutable identity', () {
    final card = cardFor({
      'id': 1,
      'username': 'alice',
      'tag': '0042',
      'profilePictureUrl': 'https://media.example/primary.jpg',
      'profilePhotos': [
        {
          'id': 9,
          'url': 'https://media.example/primary.jpg',
          'isPrimary': true,
          'createdAt': '2026-07-13T12:00:00.000Z',
        },
        {
          'id': 10,
          'url': 'https://media.example/second.jpg',
          'isPrimary': false,
          'createdAt': '2026-07-13T12:01:00.000Z',
        },
      ],
    });

    expect(card.handle, 'alice#0042');
    expect(card.photos.map((photo) => photo.id), [9, 10]);
    expect(card.photos.map((photo) => photo.url), [
      'https://media.example/primary.jpg',
      'https://media.example/second.jpg',
    ]);
  });

  test('converts expired and timed mutes into the correct visual state', () {
    final now = DateTime.utc(2026, 7, 13, 12);

    expect(
      UserCardMute.fromConversation(
        muted: true,
        mutedUntil: now.subtract(const Duration(seconds: 1)),
        now: now,
      ),
      UserCardMute.off,
    );
    expect(
      UserCardMute.fromConversation(
        muted: true,
        mutedUntil: now.add(const Duration(hours: 5)),
        now: now,
      ),
      UserCardMute.eightHours,
    );
    expect(
      UserCardMute.fromConversation(
        muted: true,
        mutedUntil: now.add(const Duration(hours: 1)),
        now: now,
      ),
      UserCardMute.oneHour,
    );
    expect(
      UserCardMute.fromConversation(
        muted: true,
        mutedUntil: now.add(const Duration(days: 3)),
        now: now,
      ),
      UserCardMute.oneWeek,
    );
    // Pin the boundaries: exactly 2h is still oneHour (<=),
    // exactly 12h is still eightHours (<=).
    expect(
      UserCardMute.fromConversation(
        muted: true,
        mutedUntil: now.add(const Duration(hours: 2)),
        now: now,
      ),
      UserCardMute.oneHour,
    );
    expect(
      UserCardMute.fromConversation(
        muted: true,
        mutedUntil: now.add(const Duration(hours: 12)),
        now: now,
      ),
      UserCardMute.eightHours,
    );
    expect(
      UserCardMute.fromConversation(muted: true, mutedUntil: null, now: now),
      UserCardMute.forever,
    );
  });
}
