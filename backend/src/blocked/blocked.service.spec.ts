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
  let friendsService: jest.Mocked<Pick<FriendsService, 'unfriend'>>;
  let conversationsService: jest.Mocked<Pick<ConversationsService, 'findByUsers' | 'delete'>>;
  let messagesService: jest.Mocked<Pick<MessagesService, 'findMediaUrlsByConversation'>>;
  let mediaCleanupService: jest.Mocked<Pick<MediaCleanupService, 'deleteMediaFile'>>;

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
            findMediaUrlsByConversation: jest.fn().mockResolvedValue([
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
    expect(friendsService.unfriend).toHaveBeenCalledWith(1, 2);
    expect(messagesService.findMediaUrlsByConversation).toHaveBeenCalledWith(55);
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/a.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/b.bin',
    );
    expect(conversationsService.delete).toHaveBeenCalledWith(55);
  });
});
