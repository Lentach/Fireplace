import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';
import { Repository } from 'typeorm';
import { ConversationsService } from '../conversations/conversations.service';
import { FriendsService } from '../friends/friends.service';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { MessagesService } from '../messages/messages.service';
import { BlockedUser } from './blocked-user.entity';
import { BlockedService } from './blocked.service';

describe('BlockedService', () => {
  let service: BlockedService;
  let blockedRepo: jest.Mocked<Repository<BlockedUser>>;
  let friendsService: jest.Mocked<
    Pick<FriendsService, 'unfriend' | 'removeFriendRequestsForPair'>
  >;
  let conversationsService: jest.Mocked<
    Pick<ConversationsService, 'findByUsers' | 'delete'>
  >;
  let messagesService: jest.Mocked<
    Pick<MessagesService, 'findMediaUrlsByConversation'>
  >;
  let mediaCleanupService: jest.Mocked<
    Pick<MediaCleanupService, 'deleteMediaFile'>
  >;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        BlockedService,
        {
          provide: getRepositoryToken(BlockedUser),
          useValue: {
            findOne: jest.fn().mockResolvedValue(null),
            create: jest.fn((value) => value),
            save: jest.fn(async (value) => value),
            delete: jest.fn(),
            find: jest.fn().mockResolvedValue([]),
            createQueryBuilder: jest.fn(),
          },
        },
        {
          provide: FriendsService,
          useValue: {
            unfriend: jest.fn().mockResolvedValue(undefined),
            removeFriendRequestsForPair: jest.fn().mockResolvedValue(0),
          },
        },
        {
          provide: ConversationsService,
          useValue: {
            findByUsers: jest.fn().mockResolvedValue({ id: 55 }),
            delete: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: MessagesService,
          useValue: {
            findMediaUrlsByConversation: jest
              .fn()
              .mockResolvedValue([
                'https://example.com/media/msgs/a.bin',
                'https://example.com/media/msgs/b.bin',
              ]),
          },
        },
        {
          provide: MediaCleanupService,
          useValue: {
            deleteMediaFile: jest.fn().mockResolvedValue(undefined),
          },
        },
      ],
    }).compile();

    service = module.get(BlockedService);
    blockedRepo = module.get(getRepositoryToken(BlockedUser));
    friendsService = module.get(FriendsService);
    conversationsService = module.get(ConversationsService);
    messagesService = module.get(MessagesService);
    mediaCleanupService = module.get(MediaCleanupService);
  });

  it('deletes self-hosted media before deleting the conversation on block', async () => {
    await service.block(1, 2);

    expect(blockedRepo.save).toHaveBeenCalled();
    expect(friendsService.removeFriendRequestsForPair).toHaveBeenCalledWith(
      1,
      2,
    );
    expect(friendsService.unfriend).not.toHaveBeenCalled();
    expect(messagesService.findMediaUrlsByConversation).toHaveBeenCalledWith(
      55,
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/a.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/b.bin',
    );
    expect(conversationsService.delete).toHaveBeenCalledWith(55);

    // Ordering invariant: the media URLs must be resolved (and the files
    // deleted) BEFORE the conversation is deleted — deleting the conversation
    // cascades away the messages, after which the URLs can no longer be
    // resolved and the files would be orphaned. A reorder must fail here.
    const deleteConvOrder =
      conversationsService.delete.mock.invocationCallOrder[0];
    expect(
      messagesService.findMediaUrlsByConversation.mock.invocationCallOrder[0],
    ).toBeLessThan(deleteConvOrder);
    for (const order of mediaCleanupService.deleteMediaFile.mock
      .invocationCallOrder) {
      expect(order).toBeLessThan(deleteConvOrder);
    }
  });

  it('throws on self-block without touching repositories or side effects', async () => {
    await expect(service.block(1, 1)).rejects.toThrow('Cannot block yourself');

    expect(blockedRepo.save).not.toHaveBeenCalled();
    expect(friendsService.unfriend).not.toHaveBeenCalled();
    expect(conversationsService.delete).not.toHaveBeenCalled();
  });

  it('self-heals a partially-applied block on retry: re-runs teardown for an already-blocked pair without re-inserting', async () => {
    const existing = { id: 7 } as BlockedUser;
    blockedRepo.findOne.mockResolvedValueOnce(existing);

    await expect(service.block(1, 2)).resolves.toBe(existing);

    // No duplicate block row is inserted...
    expect(blockedRepo.save).not.toHaveBeenCalled();
    // ...but the teardown MUST re-run so a prior block that committed the row
    // and then failed to unfriend/clean up is repaired (BE-006). The old code
    // early-returned here and left the split state permanent.
    expect(friendsService.removeFriendRequestsForPair).toHaveBeenCalledWith(
      1,
      2,
    );
    expect(conversationsService.delete).toHaveBeenCalledWith(55);
  });

  it('propagates a friend-request removal failure so the block can be retried (BE-006)', async () => {
    friendsService.removeFriendRequestsForPair.mockRejectedValueOnce(
      new Error('lock wait timeout'),
    );

    await expect(service.block(1, 2)).rejects.toThrow('lock wait timeout');

    // The block row is saved first (durable), and the critical friend-request
    // removal failure surfaces to the caller instead of being swallowed, so a
    // retry can self-heal the friendship rather than leaving it permanently.
    expect(blockedRepo.save).toHaveBeenCalled();
  });

  it('treats conversation-cleanup failure as non-fatal and still returns the saved record', async () => {
    messagesService.findMediaUrlsByConversation.mockRejectedValueOnce(
      new Error('storage down'),
    );

    const result = await service.block(1, 2);

    // The BlockedUser row is already persisted, so a cleanup failure must not
    // reject: block resolves to the same record passed to save().
    expect(blockedRepo.save).toHaveBeenCalled();
    expect(result).toBe(blockedRepo.save.mock.calls[0][0]);
    expect(conversationsService.delete).not.toHaveBeenCalled();
  });
});
