import { FriendRequestMapper } from './friend-request.mapper';
import { FriendRequest } from '../../friends/friend-request.entity';
import { FriendRequestStatus } from '../../friends/friend-request.entity';

describe('FriendRequestMapper', () => {
  it('should map FriendRequest to payload', () => {
    const request = {
      id: 1,
      sender: { id: 10, username: 'alice', tag: '0427', profilePictureUrl: null },
      receiver: { id: 20, username: 'bob', tag: '1234', profilePictureUrl: null },
      status: FriendRequestStatus.PENDING,
      createdAt: new Date('2025-01-15T12:00:00Z'),
      respondedAt: null,
    } as unknown as FriendRequest;
    const payload = FriendRequestMapper.toPayload(request);
    expect(payload).toEqual({
      id: 1,
      sender: {
        id: 10,
        username: 'alice',
        tag: '0427',
        about: null,
        profilePictureUrl: null,
        profilePhotos: [],
      },
      receiver: {
        id: 20,
        username: 'bob',
        tag: '1234',
        about: null,
        profilePictureUrl: null,
        profilePhotos: [],
      },
      status: FriendRequestStatus.PENDING,
      createdAt: request.createdAt,
      respondedAt: null,
    });
  });
});
