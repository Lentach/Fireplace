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

  it('deletes media files (only non-null) before removing expired messages', async () => {
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
    // Only the two non-null mediaUrls are deleted — the mediaUrl:null row (id 2)
    // must NOT trigger a deleteMediaFile call.
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledTimes(2);
    expect(messagesRepo.remove).toHaveBeenCalledWith(expired);

    // Ordering: every media deletion must precede the DB removal.
    const lastDelete = Math.max(
      ...mediaCleanupService.deleteMediaFile.mock.invocationCallOrder,
    );
    const firstRemove = Math.min(
      ...messagesRepo.remove.mock.invocationCallOrder,
    );
    expect(lastDelete).toBeLessThan(firstRemove);
  });

  it('retains candidates that are not actually expired (isMessageExpired guard)', async () => {
    // The coarse SQL query may return rows that are not genuinely expired;
    // the service re-filters with isMessageExpired(m, now). A future-expiry row
    // must be retained: not removed, its media not deleted.
    const expiredRow = {
      id: 1,
      mediaUrl: 'https://example.com/media/msgs/expired.bin',
      expiresAt: new Date(0),
    } as unknown as Message;
    const futureRow = {
      id: 2,
      mediaUrl: 'https://example.com/media/msgs/future.bin',
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    } as unknown as Message;
    queryBuilder.getMany.mockResolvedValue([expiredRow, futureRow]);

    await service.deleteExpiredMessages();

    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/expired.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).not.toHaveBeenCalledWith(
      'https://example.com/media/msgs/future.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledTimes(1);
    expect(messagesRepo.remove).toHaveBeenCalledWith([expiredRow]);
  });
});
