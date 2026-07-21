import { UserMapper } from './user.mapper';
import { User } from '../../users/user.entity';

describe('UserMapper', () => {
  it('should map User to payload', () => {
    const user = {
      id: 1,
      username: 'alice',
      tag: '0427',
      about: 'hey there',
      profilePictureUrl: 'https://example.com/avatar.png',
    } as User;
    const payload = UserMapper.toPayload(user);
    expect(payload).toEqual({
      id: 1,
      username: 'alice',
      tag: '0427',
      about: 'hey there',
      profilePhotos: [],
      profilePictureUrl: 'https://example.com/avatar.png',
    });
  });

  it('primary photo overrides profilePictureUrl and sorts primary first', () => {
    const user = {
      id: 3,
      username: 'carol',
      tag: '9999',
      profilePictureUrl: 'https://example.com/original.png',
      profilePhotos: [
        { id: 1, url: 'b', isPrimary: false, createdAt: new Date('2025-02-01') },
        { id: 2, url: 'a', isPrimary: true, createdAt: new Date('2025-01-01') },
      ],
    } as unknown as User;
    const payload = UserMapper.toPayload(user);
    expect(payload.profilePictureUrl).toBe('a');
    expect(payload.profilePhotos[0].id).toBe(2);
    expect(payload.profilePhotos[1].id).toBe(1);
  });

  it('sorts non-primary photos by createdAt ascending', () => {
    const user = {
      id: 4,
      username: 'dave',
      tag: '8888',
      profilePictureUrl: 'https://example.com/dave.png',
      profilePhotos: [
        { id: 10, url: 'later', isPrimary: false, createdAt: new Date('2025-03-01') },
        { id: 11, url: 'earlier', isPrimary: false, createdAt: new Date('2025-01-01') },
      ],
    } as unknown as User;
    const payload = UserMapper.toPayload(user);
    expect(payload.profilePhotos.map((p) => p.id)).toEqual([11, 10]);
    expect(payload.profilePictureUrl).toBe('https://example.com/dave.png');
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
