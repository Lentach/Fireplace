import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';
import { Repository } from 'typeorm';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { Message } from './message.entity';
import { MessageCleanupService } from './message-cleanup.service';

describe('MessageCleanupService', () => {
  let service: MessageCleanupService;
  let messagesRepo: jest.Mocked<Repository<Message>>;
  let mediaCleanupService: jest.Mocked<Pick<MediaCleanupService, 'deleteMediaFile'>>;
  let queryBuilder: {
    where: jest.Mock;
    orWhere: jest.Mock;
    getMany: jest.Mock;
  };

  beforeEach(async () => {
    queryBuilder = {
      where: jest.fn().mockReturnThis(),
      orWhere: jest.fn().mockReturnThis(),
      getMany: jest.fn().mockResolvedValue([]),
    };

    const module = await Test.createTestingModule({
      providers: [
        MessageCleanupService,
        {
          provide: getRepositoryToken(Message),
          useValue: {
            createQueryBuilder: jest.fn().mockReturnValue(queryBuilder),
            remove: jest.fn().mockResolvedValue([]),
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

    service = module.get(MessageCleanupService);
    messagesRepo = module.get(getRepositoryToken(Message));
    mediaCleanupService = module.get(MediaCleanupService);
  });

  it('deletes media files before removing expired messages', async () => {
    const expired = [
      { id: 1, mediaUrl: 'https://example.com/media/msgs/a.bin', expiresAt: new Date(0) },
      { id: 2, mediaUrl: null, expiresAt: new Date(0) },
      { id: 3, mediaUrl: 'https://example.com/media/msgs/b.bin', expiresAt: new Date(0) },
    ] as Message[];
    queryBuilder.getMany.mockResolvedValue(expired);

    await service.deleteExpiredMessages();

    expect(messagesRepo.createQueryBuilder).toHaveBeenCalledWith('m');
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/a.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/b.bin',
    );
    expect(messagesRepo.remove).toHaveBeenCalledWith(expired);
  });
});
