import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';
import { LessThan, Repository } from 'typeorm';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { Message } from './message.entity';
import { MessageCleanupService } from './message-cleanup.service';

describe('MessageCleanupService', () => {
  let service: MessageCleanupService;
  let messagesRepo: jest.Mocked<Repository<Message>>;
  let mediaCleanupService: jest.Mocked<Pick<MediaCleanupService, 'deleteMediaFile'>>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        MessageCleanupService,
        {
          provide: getRepositoryToken(Message),
          useValue: {
            find: jest.fn().mockResolvedValue([]),
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
      { id: 1, mediaUrl: 'https://example.com/media/msgs/a.bin' },
      { id: 2, mediaUrl: null },
      { id: 3, mediaUrl: 'https://example.com/media/msgs/b.bin' },
    ] as Message[];
    messagesRepo.find.mockResolvedValue(expired);

    await service.deleteExpiredMessages();

    expect(messagesRepo.find).toHaveBeenCalledWith({
      where: {
        expiresAt: expect.any(Object) as ReturnType<typeof LessThan>,
      },
    });
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/a.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/b.bin',
    );
    expect(messagesRepo.remove).toHaveBeenCalledWith(expired);
  });
});
