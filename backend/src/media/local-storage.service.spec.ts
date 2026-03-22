import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { LocalStorageService } from './local-storage.service';
import * as fs from 'fs/promises';
import * as path from 'path';

jest.mock('fs/promises');
const mockFs = fs as jest.Mocked<typeof fs>;

describe('LocalStorageService', () => {
  let service: LocalStorageService;

  beforeEach(async () => {
    jest.clearAllMocks();
    mockFs.mkdir.mockResolvedValue(undefined);
    mockFs.writeFile.mockResolvedValue(undefined);
    mockFs.unlink.mockResolvedValue(undefined);

    const module = await Test.createTestingModule({
      providers: [
        LocalStorageService,
        {
          provide: ConfigService,
          useValue: {
            get: (key: string) => {
              if (key === 'MEDIA_BASE_URL') return 'https://example.com';
              if (key === 'MEDIA_DIR') return '/app/media';
            },
          },
        },
      ],
    }).compile();

    service = module.get(LocalStorageService);
  });

  it('uploadImage returns secureUrl with /media/msgs/ path', async () => {
    const result = await service.uploadImage(1, Buffer.from('data'), 'image/jpeg');
    expect(result.secureUrl).toMatch(
      /^https:\/\/example\.com\/media\/msgs\/.+\.bin$/,
    );
    expect(mockFs.writeFile).toHaveBeenCalled();
  });

  it('uploadAvatar returns secureUrl with /media/avatars/ path and .jpg extension', async () => {
    const result = await service.uploadAvatar(1, Buffer.from('data'), 'image/jpeg');
    expect(result.secureUrl).toMatch(
      /^https:\/\/example\.com\/media\/avatars\/.+\.jpg$/,
    );
  });

  it('uploadVoiceMessage returns provided duration', async () => {
    const result = await service.uploadVoiceMessage(
      1,
      Buffer.from('data'),
      'audio/m4a',
      42,
    );
    expect(result.duration).toBe(42);
    expect(result.secureUrl).toMatch(/\.bin$/);
  });

  it('uploadRawFile returns secureUrl with .bin extension', async () => {
    const result = await service.uploadRawFile(
      1,
      Buffer.from('data'),
      'application/pdf',
      'doc.pdf',
    );
    expect(result.secureUrl).toMatch(/\.bin$/);
  });

  it('deleteFile calls unlink with correct path', async () => {
    await service.deleteFile('msgs/abc123.bin');
    expect(mockFs.unlink).toHaveBeenCalledWith(
      path.join('/app/media', 'msgs/abc123.bin'),
    );
  });

  it('deleteFile is a no-op for Cloudinary URLs (skips)', async () => {
    await service.deleteFile(
      'https://res.cloudinary.com/demo/image/upload/sample.jpg',
    );
    expect(mockFs.unlink).not.toHaveBeenCalled();
  });

  it('deleteFile does not throw if file not found', async () => {
    const err = Object.assign(new Error(), { code: 'ENOENT' });
    mockFs.unlink.mockRejectedValueOnce(err);
    await expect(service.deleteFile('msgs/missing.bin')).resolves.not.toThrow();
  });
});
