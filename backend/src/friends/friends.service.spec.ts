import { DataSource, Repository } from 'typeorm';
import { FriendRequest, FriendRequestStatus } from './friend-request.entity';
import { FriendsService } from './friends.service';

describe('FriendsService', () => {
  const friendRequestRepository = {
    find: jest.fn(),
  } as unknown as jest.Mocked<Repository<FriendRequest>>;
  const service = new FriendsService(
    friendRequestRepository,
    {} as DataSource,
  );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('loads profile photos for each user returned to the contacts list', async () => {
    const friend = {
      id: 2,
      username: 'friend',
      tag: '0002',
      profilePhotos: [{ id: 12, url: '/avatars/friend.jpg', isPrimary: true }],
    } as any;
    friendRequestRepository.find.mockResolvedValue([
      {
        id: 1,
        status: FriendRequestStatus.ACCEPTED,
        sender: { id: 1 },
        receiver: friend,
      } as FriendRequest,
    ]);

    await expect(service.getFriends(1)).resolves.toEqual([friend]);
    expect(friendRequestRepository.find).toHaveBeenCalledWith(
      expect.objectContaining({
        relations: {
          sender: { profilePhotos: true },
          receiver: { profilePhotos: true },
        },
      }),
    );
  });
});
