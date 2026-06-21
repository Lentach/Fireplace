import { Test } from '@nestjs/testing';
import { MediaController } from './media.controller';
import { LocalStorageService } from './local-storage.service';
import { ThrottlerModule } from '@nestjs/throttler';
import { BadRequestException } from '@nestjs/common';

const mockStorage = {
  uploadImage: jest.fn().mockResolvedValue({
    secureUrl: 'https://example.com/media/msgs/abc.bin',
    publicId: 'msgs/abc.bin',
  }),
  uploadVoiceMessage: jest.fn().mockResolvedValue({
    secureUrl: 'https://example.com/media/msgs/abc.bin',
    publicId: 'msgs/abc.bin',
    duration: 5,
  }),
  uploadRawFile: jest.fn().mockResolvedValue({
    secureUrl: 'https://example.com/media/msgs/abc.bin',
    publicId: 'msgs/abc.bin',
  }),
  uploadAvatar: jest.fn().mockResolvedValue({
    secureUrl: 'https://example.com/media/avatars/abc.jpg',
    publicId: 'avatars/abc.jpg',
  }),
};

const fakeFile = (size = 100, mime = 'application/octet-stream') =>
  ({
    buffer: Buffer.alloc(size),
    mimetype: mime,
    size,
    originalname: 'test.bin',
  }) as Express.Multer.File;

const fakeReq = { user: { id: 1 } } as any;
const fakeRes = {
  setHeader: jest.fn(),
  status: jest.fn().mockReturnThis(),
  send: jest.fn(),
  sendFile: jest.fn(),
} as any;

describe('MediaController', () => {
  let controller: MediaController;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module = await Test.createTestingModule({
      imports: [ThrottlerModule.forRoot([{ ttl: 60000, limit: 100 }])],
      controllers: [MediaController],
      providers: [{ provide: LocalStorageService, useValue: mockStorage }],
    }).compile();
    controller = module.get(MediaController);
  });

  it('upload image returns mediaUrl', async () => {
    const result = await controller.upload(
      fakeFile(),
      { mediaType: 'image' } as any,
      fakeReq,
    );
    expect(result).toEqual({
      mediaUrl: 'https://example.com/media/msgs/abc.bin',
    });
    expect(mockStorage.uploadImage).toHaveBeenCalledWith(
      1,
      expect.any(Buffer),
      'application/octet-stream',
    );
  });

  it('upload voice returns mediaUrl + mediaDuration', async () => {
    const result = await controller.upload(
      fakeFile(),
      { mediaType: 'voice', duration: 5 } as any,
      fakeReq,
    );
    expect(result).toMatchObject({
      mediaUrl: expect.any(String),
      mediaDuration: 5,
    });
  });

  it('upload without file throws BadRequestException', async () => {
    await expect(
      controller.upload(
        undefined as any,
        { mediaType: 'image' } as any,
        fakeReq,
      ),
    ).rejects.toThrow(BadRequestException);
  });

  // By default (MEDIA_X_ACCEL_REDIRECT unset) the controller serves the file directly,
  // independent of NODE_ENV — prod must NOT fall back to an empty X-Accel response.
  it('serveMsgs serves file directly by default', async () => {
    await controller.serveMsgs('abc.bin', fakeRes);
    expect(fakeRes.sendFile).toHaveBeenCalledWith(
      expect.stringMatching(/msgs[/\\]abc\.bin/),
    );
  });

  it('serveAvatars serves file directly by default', async () => {
    await controller.serveAvatars('uuid.jpg', fakeRes);
    expect(fakeRes.sendFile).toHaveBeenCalledWith(
      expect.stringMatching(/avatars[/\\]uuid\.jpg/),
    );
  });
});
