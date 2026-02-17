import { FriendRequestMapper } from './friend-request.mapper';
import { FriendRequest } from '../../friends/friend-request.entity';
import { FriendRequestStatus } from '../../friends/friend-request.entity';

describe('FriendRequestMapper', () => {
  it('should map FriendRequest to payload', () => {
    const request = {
      id: 1,
      sender: { id: 10, email: 'a@x.com', username: 'alice', profilePictureUrl: null },
      receiver: { id: 20, email: 'b@x.com', username: 'bob', profilePictureUrl: null },
      status: FriendRequestStatus.PENDING,
      createdAt: new Date('2025-01-15T12:00:00Z'),
      respondedAt: null,
    } as unknown as FriendRequest;
    const payload = FriendRequestMapper.toPayload(request);
    expect(payload).toEqual({
      id: 1,
      sender: { id: 10, email: 'a@x.com', username: 'alice', profilePictureUrl: null },
      receiver: { id: 20, email: 'b@x.com', username: 'bob', profilePictureUrl: null },
      status: FriendRequestStatus.PENDING,
      createdAt: request.createdAt,
      respondedAt: null,
    });
  });
});
