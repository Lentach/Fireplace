import { UserMapper } from './user.mapper';
import { User } from '../../users/user.entity';

describe('UserMapper', () => {
  it('should map User to payload', () => {
    const user = {
      id: 1,
      username: 'alice',
      tag: '0427',
      profilePictureUrl: 'https://example.com/avatar.png',
    } as User;
    const payload = UserMapper.toPayload(user);
    expect(payload).toEqual({
      id: 1,
      username: 'alice',
      tag: '0427',
      about: null,
      profilePhotos: [],
      profilePictureUrl: 'https://example.com/avatar.png',
    });
  });

  it('should handle null profilePictureUrl', () => {
    const user = {
      id: 2,
      username: 'bob',
      tag: '1234',
      profilePictureUrl: null,
    } as unknown as User;
    const payload = UserMapper.toPayload(user);
    expect(payload).toEqual({
      id: 2,
      username: 'bob',
      tag: '1234',
      about: null,
      profilePhotos: [],
      profilePictureUrl: null,
    });
  });
});
