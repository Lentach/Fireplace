import { ConflictException, NotFoundException } from '@nestjs/common';
import { DataSource, Repository, UpdateResult } from 'typeorm';
import { FriendRequest, FriendRequestStatus } from './friend-request.entity';
import { FriendsService } from './friends.service';
import { BlockedService } from '../blocked/blocked.service';
import { User } from '../users/user.entity';

// Test fixtures are intentionally partial entities; a single justified cast
// keeps the specs free of scattered `any`.
const frow = (data: Partial<FriendRequest>): FriendRequest =>
  data as unknown as FriendRequest;
const usr = (data: Partial<User>): User => data as unknown as User;
// TypeORM's UpdateResult only exposes `affected` to these paths; one typed cast
// keeps the conditional-transition specs free of scattered `any`.
const upd = (affected: number): UpdateResult =>
  ({ affected }) as unknown as UpdateResult;

describe('FriendsService', () => {
  let friendRequestRepository: jest.Mocked<Repository<FriendRequest>>;
  let dataSource: jest.Mocked<Pick<DataSource, 'transaction'>>;
  let manager: {
    findOne: jest.Mock;
    create: jest.Mock;
    save: jest.Mock;
    update: jest.Mock;
    createQueryBuilder: jest.Mock;
  };
  let deleteBuilder: {
    delete: jest.Mock;
    from: jest.Mock;
    where: jest.Mock;
    execute: jest.Mock;
  };
  let service: FriendsService;
  let blockedService: {
    isBlockedByEither: jest.Mock;
    getBlockedUserIds: jest.Mock;
    getBlockedByUserIds: jest.Mock;
  };

  beforeEach(() => {
    friendRequestRepository = {
      find: jest.fn(),
      findOne: jest.fn(),
      update: jest.fn().mockResolvedValue(upd(1)),
      createQueryBuilder: jest.fn(),
    } as unknown as jest.Mocked<Repository<FriendRequest>>;

    deleteBuilder = {
      delete: jest.fn().mockReturnThis(),
      from: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      execute: jest.fn().mockResolvedValue({ affected: 0 }),
    };

    manager = {
      findOne: jest.fn(),
      create: jest.fn((_entity, data) => data),
      save: jest.fn(async (_entity, value) => value),
      update: jest.fn().mockResolvedValue(undefined),
      createQueryBuilder: jest.fn(() => deleteBuilder),
    };

    dataSource = {
      transaction: jest.fn(async (cb: (m: unknown) => Promise<unknown>) =>
        cb(manager),
      ),
    } as unknown as jest.Mocked<Pick<DataSource, 'transaction'>>;

    blockedService = {
      isBlockedByEither: jest.fn().mockResolvedValue(false),
      getBlockedUserIds: jest.fn().mockResolvedValue([]),
      getBlockedByUserIds: jest.fn().mockResolvedValue([]),
    };

    service = new FriendsService(
      friendRequestRepository,
      dataSource as unknown as DataSource,
      blockedService as unknown as BlockedService,
    );
  });

  describe('getSentRequests', () => {
    it('loads pending requests sent by the user with both participants ordered newest first', async () => {
      const sentRequest = frow({
        id: 10,
        status: FriendRequestStatus.PENDING,
        sender: usr({ id: 1 }),
        receiver: usr({ id: 2 }),
      });
      friendRequestRepository.find.mockResolvedValue([sentRequest]);

      await expect(service.getSentRequests(1)).resolves.toEqual([sentRequest]);

      expect(friendRequestRepository.find).toHaveBeenCalledWith({
        where: {
          sender: { id: 1 },
          status: FriendRequestStatus.PENDING,
        },
        relations: {
          sender: true,
          receiver: true,
        },
        order: { createdAt: 'DESC' },
      });
    });
  });
  describe('getFriends', () => {
    it('loads profile photos for each user returned to the contacts list', async () => {
      const friend = usr({
        id: 2,
        username: 'friend',
        tag: '0002',
        profilePhotos: [
          { id: 12, url: '/avatars/friend.jpg', isPrimary: true },
        ],
      } as Partial<User>);
      friendRequestRepository.find.mockResolvedValue([
        frow({
          id: 1,
          status: FriendRequestStatus.ACCEPTED,
          sender: usr({ id: 1 }),
          receiver: friend,
        }),
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

    it('deduplicates counterparts and picks the correct "other" participant per direction', async () => {
      const userA = usr({ id: 2, username: 'a' });
      const userB = usr({ id: 3, username: 'b' });
      friendRequestRepository.find.mockResolvedValue([
        // userId=1 is the sender here -> counterpart is the receiver (userA)
        frow({
          id: 10,
          status: FriendRequestStatus.ACCEPTED,
          sender: usr({ id: 1 }),
          receiver: userA,
        }),
        // duplicate pair (same 1<->2) must not produce a second userA entry
        frow({
          id: 11,
          status: FriendRequestStatus.ACCEPTED,
          sender: usr({ id: 1 }),
          receiver: userA,
        }),
        // userId=1 is the receiver here -> counterpart is the sender (userB)
        frow({
          id: 12,
          status: FriendRequestStatus.ACCEPTED,
          sender: userB,
          receiver: usr({ id: 1 }),
        }),
      ]);

      await expect(service.getFriends(1)).resolves.toEqual([userA, userB]);
    });
  });

  describe('sendRequest', () => {
    it('rejects a self-request without hitting the repository', async () => {
      await expect(
        service.sendRequest(usr({ id: 1 }), usr({ id: 1 })),
      ).rejects.toThrow(ConflictException);
      await expect(
        service.sendRequest(usr({ id: 1 }), usr({ id: 1 })),
      ).rejects.toThrow('Cannot send friend request to yourself');
      expect(friendRequestRepository.findOne).not.toHaveBeenCalled();
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('rejects when the pair is already accepted (either direction)', async () => {
      friendRequestRepository.findOne.mockResolvedValueOnce(
        frow({ id: 1, status: FriendRequestStatus.ACCEPTED }),
      );

      await expect(
        service.sendRequest(usr({ id: 1 }), usr({ id: 2 })),
      ).rejects.toThrow('Already friends');
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('rejects a duplicate pending request', async () => {
      friendRequestRepository.findOne
        .mockResolvedValueOnce(null) // no accepted
        .mockResolvedValueOnce(
          frow({ id: 2, status: FriendRequestStatus.PENDING }),
        ); // existing pending

      await expect(
        service.sendRequest(usr({ id: 1 }), usr({ id: 2 })),
      ).rejects.toThrow('Friend request already sent');
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('auto-accepts both rows when a reverse pending request exists', async () => {
      friendRequestRepository.findOne
        .mockResolvedValueOnce(null) // no accepted
        .mockResolvedValueOnce(null); // no forward pending
      // reverse pending row found inside the transaction, then reload
      manager.findOne
        .mockResolvedValueOnce(frow({ id: 99 })) // reverse pending
        .mockResolvedValueOnce(
          frow({ id: 100, status: FriendRequestStatus.ACCEPTED }),
        ); // reload of the new request
      manager.create.mockReturnValueOnce(
        frow({ id: 100, status: FriendRequestStatus.PENDING }),
      );

      const result = await service.sendRequest(usr({ id: 1 }), usr({ id: 2 }));

      // Both the reverse (99) and the newly created (100) rows flip to ACCEPTED.
      expect(manager.update).toHaveBeenCalledWith(
        FriendRequest,
        { id: 99 },
        expect.objectContaining({ status: FriendRequestStatus.ACCEPTED }),
      );
      expect(manager.update).toHaveBeenCalledWith(
        FriendRequest,
        { id: 100 },
        expect.objectContaining({ status: FriendRequestStatus.ACCEPTED }),
      );
      // respondedAt is stamped on the accepted rows.
      expect(manager.update.mock.calls[0][2].respondedAt).toBeInstanceOf(Date);
      expect(result).toEqual(
        frow({ id: 100, status: FriendRequestStatus.ACCEPTED }),
      );
    });

    it('clears a prior REJECTED row before creating the fresh request on re-send', async () => {
      friendRequestRepository.findOne
        .mockResolvedValueOnce(null) // no accepted
        .mockResolvedValueOnce(null); // no forward pending
      manager.findOne.mockResolvedValueOnce(null); // no reverse pending

      await service.sendRequest(usr({ id: 1 }), usr({ id: 2 }));

      // The REJECTED-row delete must run, scoped to the exact pair + status,
      // and it must precede the create so the UNIQUE(sender,receiver) index
      // does not collide on re-send.
      expect(deleteBuilder.where).toHaveBeenCalledWith(
        expect.stringContaining('status = :status'),
        expect.objectContaining({
          senderId: 1,
          receiverId: 2,
          status: FriendRequestStatus.REJECTED,
        }),
      );
      expect(deleteBuilder.execute).toHaveBeenCalledTimes(1);
      expect(deleteBuilder.execute.mock.invocationCallOrder[0]).toBeLessThan(
        manager.create.mock.invocationCallOrder[0],
      );
    });
  });

  describe('acceptRequest', () => {
    it('throws NotFoundException when the request does not exist', async () => {
      friendRequestRepository.findOne.mockResolvedValueOnce(null);

      await expect(service.acceptRequest(5, 1)).rejects.toThrow(
        NotFoundException,
      );
      expect(friendRequestRepository.update).not.toHaveBeenCalled();
    });

    it('throws ConflictException when the actor is not the receiver', async () => {
      friendRequestRepository.findOne.mockResolvedValueOnce(
        frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
      );

      await expect(service.acceptRequest(5, 99)).rejects.toThrow(
        'Only receiver can accept this request',
      );
      expect(friendRequestRepository.update).not.toHaveBeenCalled();
    });

    it('marks the request ACCEPTED with respondedAt and returns the reloaded row', async () => {
      const reloaded = frow({ id: 5, status: FriendRequestStatus.ACCEPTED });
      friendRequestRepository.findOne
        .mockResolvedValueOnce(
          frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
        )
        .mockResolvedValueOnce(reloaded);

      await expect(service.acceptRequest(5, 2)).resolves.toBe(reloaded);
      expect(friendRequestRepository.update).toHaveBeenCalledWith(
        { id: 5, status: FriendRequestStatus.PENDING },
        expect.objectContaining({
          status: FriendRequestStatus.ACCEPTED,
          respondedAt: expect.any(Date),
        }),
      );
    });

    it('refuses to accept when either user has blocked the other (BE-101)', async () => {
      friendRequestRepository.findOne.mockResolvedValueOnce(
        frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
      );
      blockedService.isBlockedByEither.mockResolvedValueOnce(true);

      await expect(service.acceptRequest(5, 2)).rejects.toThrow(
        'Cannot accept a request from a blocked user',
      );
      expect(blockedService.isBlockedByEither).toHaveBeenCalledWith(1, 2);
      expect(friendRequestRepository.update).not.toHaveBeenCalled();
    });

    it('does NOT resurrect a REJECTED request to ACCEPTED (BE-102)', async () => {
      friendRequestRepository.findOne
        .mockResolvedValueOnce(
          frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
        )
        .mockResolvedValueOnce(
          frow({ id: 5, status: FriendRequestStatus.REJECTED }),
        );
      // Conditional update matched no PENDING row.
      friendRequestRepository.update.mockResolvedValueOnce(upd(0));

      await expect(service.acceptRequest(5, 2)).rejects.toThrow(
        'Friend request is no longer pending',
      );
      // The transition is attempted with the PENDING guard, so a REJECTED row
      // is never flipped to ACCEPTED.
      expect(friendRequestRepository.update).toHaveBeenCalledWith(
        { id: 5, status: FriendRequestStatus.PENDING },
        expect.objectContaining({ status: FriendRequestStatus.ACCEPTED }),
      );
    });

    it('stays idempotent when a concurrent double-tap already accepted (BE-102)', async () => {
      const alreadyAccepted = frow({
        id: 5,
        status: FriendRequestStatus.ACCEPTED,
      });
      friendRequestRepository.findOne
        .mockResolvedValueOnce(
          frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
        )
        .mockResolvedValueOnce(alreadyAccepted);
      friendRequestRepository.update.mockResolvedValueOnce(upd(0));

      // The losing handler must not throw a hard error; it returns the row the
      // winning handler already accepted.
      await expect(service.acceptRequest(5, 2)).resolves.toBe(alreadyAccepted);
    });
  });

  describe('rejectRequest', () => {
    it('throws NotFoundException when the request does not exist', async () => {
      friendRequestRepository.findOne.mockResolvedValueOnce(null);

      await expect(service.rejectRequest(5, 1)).rejects.toThrow(
        NotFoundException,
      );
      expect(friendRequestRepository.update).not.toHaveBeenCalled();
    });

    it('throws ConflictException when the actor is not the receiver', async () => {
      friendRequestRepository.findOne.mockResolvedValueOnce(
        frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
      );

      await expect(service.rejectRequest(5, 99)).rejects.toThrow(
        'Only receiver can reject this request',
      );
      expect(friendRequestRepository.update).not.toHaveBeenCalled();
    });

    it('marks the request REJECTED with respondedAt and returns the reloaded row', async () => {
      const reloaded = frow({ id: 5, status: FriendRequestStatus.REJECTED });
      friendRequestRepository.findOne
        .mockResolvedValueOnce(
          frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
        )
        .mockResolvedValueOnce(reloaded);

      await expect(service.rejectRequest(5, 2)).resolves.toBe(reloaded);
      expect(friendRequestRepository.update).toHaveBeenCalledWith(
        { id: 5, status: FriendRequestStatus.PENDING },
        expect.objectContaining({
          status: FriendRequestStatus.REJECTED,
          respondedAt: expect.any(Date),
        }),
      );
    });

    it('does NOT flip an already ACCEPTED request to REJECTED (BE-102)', async () => {
      friendRequestRepository.findOne
        .mockResolvedValueOnce(
          frow({ id: 5, receiver: usr({ id: 2 }), sender: usr({ id: 1 }) }),
        )
        .mockResolvedValueOnce(
          frow({ id: 5, status: FriendRequestStatus.ACCEPTED }),
        );
      friendRequestRepository.update.mockResolvedValueOnce(upd(0));

      await expect(service.rejectRequest(5, 2)).rejects.toThrow(
        'Friend request is no longer pending',
      );
      expect(friendRequestRepository.update).toHaveBeenCalledWith(
        { id: 5, status: FriendRequestStatus.PENDING },
        expect.objectContaining({ status: FriendRequestStatus.REJECTED }),
      );
    });
  });

  describe('getPendingRequests', () => {
    it('hides pending requests from users the caller blocked or was blocked by (BE-101)', async () => {
      friendRequestRepository.find.mockResolvedValueOnce([
        frow({ id: 1, sender: usr({ id: 2 }), receiver: usr({ id: 1 }) }),
        frow({ id: 2, sender: usr({ id: 3 }), receiver: usr({ id: 1 }) }),
        frow({ id: 3, sender: usr({ id: 4 }), receiver: usr({ id: 1 }) }),
      ]);
      blockedService.getBlockedUserIds.mockResolvedValueOnce([2]); // caller blocked user 2
      blockedService.getBlockedByUserIds.mockResolvedValueOnce([3]); // user 3 blocked caller

      const result = await service.getPendingRequests(1);

      // Only the request from the un-blocked sender (4) survives the filter.
      expect(result.map((r) => r.id)).toEqual([3]);
    });
  });

  describe('removeFriendRequestsForPair', () => {
    it('deletes every request between the pair in both directions regardless of status (BE-101)', async () => {
      const qb = {
        delete: jest.fn().mockReturnThis(),
        from: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        execute: jest.fn().mockResolvedValue({ affected: 2 }),
      };
      (friendRequestRepository.createQueryBuilder as jest.Mock).mockReturnValue(
        qb,
      );

      await expect(service.removeFriendRequestsForPair(1, 2)).resolves.toBe(2);

      // The predicate must cover BOTH directions so no orphan row survives the
      // block; a one-directional delete would leave a resurrectable request.
      expect(qb.where).toHaveBeenCalledWith(
        expect.stringContaining('receiver_id = :a'),
        { a: 1, b: 2 },
      );
    });
  });
});
