import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('fromJson parses user', () {
      final json = {
        'id': 1,
        'username': 'testuser',
        'tag': '0427',
      };
      final user = UserModel.fromJson(json);
      expect(user.id, 1);
      expect(user.username, 'testuser');
      expect(user.tag, '0427');
      expect(user.profilePictureUrl, isNull);
      expect(user.displayHandle, 'testuser#0427');
    });

    test('fromJson parses full user', () {
      final json = {
        'id': 2,
        'username': 'testuser',
        'tag': '1234',
        'profilePictureUrl': 'https://example.com/avatar.png',
      };
      final user = UserModel.fromJson(json);
      expect(user.id, 2);
      expect(user.username, 'testuser');
      expect(user.tag, '1234');
      expect(user.profilePictureUrl, 'https://example.com/avatar.png');
    });

    test('copyWith preserves unchanged fields', () {
      final user = UserModel(id: 1, username: 'old', tag: '0001');
      final updated = user.copyWith(username: 'new');
      expect(updated.id, 1);
      expect(updated.username, 'new');
      expect(updated.tag, '0001');
    });
  });
}
