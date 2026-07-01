import { Test } from '@nestjs/testing';
import { MediaController } from './media.controller';
import { LocalStorageService } from './local-storage.service';
import { ThrottlerModule } from '@nestjs/throttler';
import { BadRequestException } from '@nestjs/common';
import { GUARDS_METADATA, INTERCEPTORS_METADATA } from '@nestjs/common/constants';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

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

function isObject(value: unknown): value is Record<PropertyKey, unknown> {
  return value !== null && typeof value === 'object';
}

function hasMulterFileSize(
  value: unknown,
): value is { multer: { limits: { fileSize: number } } } {
  if (!isObject(value)) return false;
  const multer = value.multer;
  if (!isObject(multer)) return false;
  const limits = multer.limits;
  if (!isObject(limits)) return false;
  return typeof limits.fileSize === 'number';
}

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

  it('guards upload and message media fetch with JWT auth', () => {
    for (const methodName of ['upload', 'serveMsgs'] as const) {
      const guards = Reflect.getMetadata(
        GUARDS_METADATA,
        MediaController.prototype[methodName],
      );

      expect(Array.isArray(guards)).toBe(true);
      expect(guards).toContain(JwtAuthGuard);
    }
  });

  it('upload interceptor carries the 21 MiB Multer file-size limit', () => {
    const interceptors = Reflect.getMetadata(
      INTERCEPTORS_METADATA,
      MediaController.prototype.upload,
    );

    expect(Array.isArray(interceptors)).toBe(true);
    if (!Array.isArray(interceptors)) {
      throw new Error('Upload interceptors metadata is missing.');
    }
    const UploadInterceptor = interceptors[0];
    expect(typeof UploadInterceptor).toBe('function');
    if (typeof UploadInterceptor !== 'function') {
      throw new Error('Upload interceptor metadata is not a function.');
    }

    const interceptor = Reflect.construct(UploadInterceptor, []);
    expect(hasMulterFileSize(interceptor)).toBe(true);
    if (!hasMulterFileSize(interceptor)) {
      throw new Error('Upload interceptor does not expose a Multer file limit.');
    }

    expect(interceptor.multer.limits.fileSize).toBe(21 * 1024 * 1024);
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

  it('upload avatar rejects spoofed image MIME when bytes are not JPEG or PNG', async () => {
    const spoofedPng = fakeFile(Buffer.byteLength('not-an-image'), 'image/png');
    spoofedPng.buffer = Buffer.from('not-an-image');
    spoofedPng.originalname = 'avatar.png';

    await expect(
      controller.upload(spoofedPng, { mediaType: 'avatar' }, fakeReq),
    ).rejects.toThrow('Avatar must be a JPEG or PNG image.');
    expect(mockStorage.uploadAvatar).not.toHaveBeenCalled();
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

  it.each([
    {
      mediaKind: 'message media',
      serve: (filename: string) => controller.serveMsgs(filename, fakeRes),
    },
    {
      mediaKind: 'avatars',
      serve: (filename: string) => controller.serveAvatars(filename, fakeRes),
    },
  ])('$mediaKind rejects path traversal filenames before sending a file', async ({ serve }) => {
    await expect(serve('../secret.bin')).rejects.toThrow(BadRequestException);
    expect(fakeRes.sendFile).not.toHaveBeenCalled();
  });
});
