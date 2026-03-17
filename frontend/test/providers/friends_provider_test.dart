import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/models/user_model.dart';

void main() {
  group('FriendsProvider', () {
    test('onConnect(false) clears all state and blockedByUserIds', () {
      final provider = FriendsProvider();

      provider.onConnect(false);

      expect(provider.friends, isEmpty);
      expect(provider.friendRequests, isEmpty);
      expect(provider.pendingRequestsCount, 0);
      expect(provider.blockedUsers, isEmpty);
      expect(provider.blockedByUserIds, isEmpty);
      expect(provider.searchResults, isNull);
      expect(provider.pendingFriendAcceptedByName, isNull);
    });

    test('onConnect(true) clears blockedByUserIds', () {
      final provider = FriendsProvider();

      // Use the proper API to add a blocked-by entry
      provider.onYouWereBlocked({'userId': 42});
      expect(provider.blockedByUserIds, contains(42));

      provider.onConnect(true);

      expect(provider.blockedByUserIds, isEmpty);
      expect(provider.searchResults, isNull);
      expect(provider.pendingFriendAcceptedByName, isNull);
    });

    test('onYouWereBlocked adds to blockedByUserIds and removes friend', () {
      final provider = FriendsProvider();
      provider.onConnect(false);

      final user = UserModel(id: 5, username: 'bob', tag: '0005');
      final friendJson = {
        'id': user.id,
        'username': user.username,
        'tag': user.tag,
      };

      provider.onFriendsList([friendJson]);
      expect(provider.friends.length, 1);

      provider.onYouWereBlocked({'userId': user.id});

      expect(provider.blockedByUserIds.contains(user.id), isTrue);
      expect(provider.friends, isEmpty);
    });

    test('onBlockedList removes blocked friends from friends list', () {
      final provider = FriendsProvider();

      final alice = UserModel(id: 1, username: 'alice', tag: '0001');
      final bob = UserModel(id: 2, username: 'bob', tag: '0002');

      provider.onFriendsList([
        {'id': alice.id, 'username': alice.username, 'tag': alice.tag},
        {'id': bob.id, 'username': bob.username, 'tag': bob.tag},
      ]);
      expect(provider.friends.length, 2);

      provider.onBlockedList([
        {'id': bob.id, 'username': bob.username, 'tag': bob.tag},
      ]);

      expect(provider.blockedUsers.length, 1);
      expect(provider.blockedUsers.first.id, bob.id);
      expect(provider.friends.length, 1);
      expect(provider.friends.first.id, alice.id);
    });
  });
}

