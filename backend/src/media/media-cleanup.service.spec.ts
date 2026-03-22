import { Test } from '@nestjs/testing';
import { MediaCleanupService } from './media-cleanup.service';
import { LocalStorageService } from './local-storage.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Message } from '../messages/message.entity';

const mockStorage = {
  deleteFile: jest.fn().mockResolvedValue(undefined),
  extractPublicId: jest.fn((url: string) =>
    url.replace('https://example.com/media/', ''),
  ),
};
const mockMessageRepo = { createQueryBuilder: jest.fn() };

describe('MediaCleanupService', () => {
  let service: MediaCleanupService;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module = await Test.createTestingModule({
      providers: [
        MediaCleanupService,
        { provide: LocalStorageService, useValue: mockStorage },
        { provide: getRepositoryToken(Message), useValue: mockMessageRepo },
        { provide: 'MEDIA_BASE_URL', useValue: 'https://example.com' },
        { provide: 'MEDIA_DIR', useValue: '/app/media' },
      ],
    }).compile();
    service = module.get(MediaCleanupService);
  });

  it('deleteMediaFile skips null mediaUrl', async () => {
    await service.deleteMediaFile(null);
    expect(mockStorage.deleteFile).not.toHaveBeenCalled();
  });

  it('deleteMediaFile skips Cloudinary URLs', async () => {
    await service.deleteMediaFile(
      'https://res.cloudinary.com/demo/image/upload/sample.jpg',
    );
    expect(mockStorage.deleteFile).not.toHaveBeenCalled();
  });

  it('deleteMediaFile calls deleteFile with publicId for self-hosted URLs', async () => {
    await service.deleteMediaFile('https://example.com/media/msgs/abc.bin');
    expect(mockStorage.extractPublicId).toHaveBeenCalledWith(
      'https://example.com/media/msgs/abc.bin',
    );
    expect(mockStorage.deleteFile).toHaveBeenCalledWith('msgs/abc.bin');
  });

  it('deleteMediaFile does not throw on storage error', async () => {
    mockStorage.deleteFile.mockRejectedValueOnce(new Error('disk error'));
    await expect(
      service.deleteMediaFile('https://example.com/media/msgs/abc.bin'),
    ).resolves.not.toThrow();
  });
});
