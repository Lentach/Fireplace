import { UserMapper } from './user.mapper';
import { User } from '../../users/user.entity';

describe('UserMapper', () => {
  it('should map User to payload', () => {
    const user = {
      id: 1,
      email: 'alice@example.com',
      username: 'alice',
      profilePictureUrl: 'https://example.com/avatar.png',
    } as User;
    const payload = UserMapper.toPayload(user);
    expect(payload).toEqual({
      id: 1,
      email: 'alice@example.com',
      username: 'alice',
      profilePictureUrl: 'https://example.com/avatar.png',
    });
  });

  it('should handle null username', () => {
    const user = {
      id: 2,
      email: 'bob@example.com',
      username: null,
      profilePictureUrl: null,
    } as unknown as User;
    const payload = UserMapper.toPayload(user);
    expect(payload).toEqual({
      id: 2,
      email: 'bob@example.com',
      username: null,
      profilePictureUrl: null,
    });
  });
});
