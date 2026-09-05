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

// Decorator metadata hangs off the FUNCTION OBJECT stored on the prototype, so these
// tests must read that object without ever invoking it. Writing
// `MediaController.prototype.upload` says "unbound method" to typescript-eslint (and
// 8.65 started catching the computed `prototype[name]` form too), which is the wrong
// signal: nothing here is ever called. Go through the property descriptor instead —
// same object, and it states the intent.
function controllerMethod(name: 'upload' | 'serveMsgs'): object {
  const descriptor = Object.getOwnPropertyDescriptor(
    MediaController.prototype,
    name,
  );
  const value: unknown = descriptor?.value;
  if (typeof value !== 'function') {
    throw new Error(`MediaController.prototype.${name} is not a method.`);
  }
  return value;
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
        controllerMethod(methodName),
      );

      expect(Array.isArray(guards)).toBe(true);
      expect(guards).toContain(JwtAuthGuard);
    }
  });

  it('upload interceptor carries the 21 MiB Multer file-size limit', () => {
    const interceptors = Reflect.getMetadata(
      INTERCEPTORS_METADATA,
      controllerMethod('upload'),
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

  it('upload file returns mediaUrl + fileName from dto', async () => {
    const result = await controller.upload(
      fakeFile(),
      { mediaType: 'file', fileName: 'doc.pdf' },
      fakeReq,
    );
    expect(result).toEqual({
      mediaUrl: expect.any(String),
      fileName: 'doc.pdf',
    });
    expect(mockStorage.uploadRawFile).toHaveBeenCalled();
  });

  it('upload file falls back to originalname when fileName omitted', async () => {
    const result = await controller.upload(
      fakeFile(),
      { mediaType: 'file' },
      fakeReq,
    );
    expect(result).toEqual({
      mediaUrl: expect.any(String),
      fileName: 'test.bin',
    });
    expect(mockStorage.uploadRawFile).toHaveBeenCalled();
  });

  it('upload video routes through the opaque msgs/ blob path and echoes mediaDuration', async () => {
    const result = await controller.upload(
      fakeFile(),
      { mediaType: 'video', duration: 30 },
      fakeReq,
    );
    expect(result).toEqual({
      mediaUrl: 'https://example.com/media/msgs/abc.bin',
      mediaDuration: 30,
    });
    expect(mockStorage.uploadRawFile).toHaveBeenCalledWith(
      1,
      expect.any(Buffer),
      'application/octet-stream',
    );
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

  // Regression for the 2026-09-06 phone lockout: with a 60/min limit and no
  // cache header, inline video autoplay + fullscreen re-downloads in ONE chat
  // tripped 429 and every later media load failed. Blobs are immutable, so
  // the client may cache them; the throttle stays only as a scrape brake.
  it('serveMsgs marks the immutable blob privately cacheable and is not throttled at chat pace', async () => {
    await controller.serveMsgs('abc.bin', fakeRes);
    // Direct-serve path: the header rides on the SUCCESSFUL sendFile only —
    // a 404 from sendFile must not carry a year-long immutable cache.
    expect(fakeRes.setHeader).not.toHaveBeenCalledWith(
      'Cache-Control',
      expect.anything(),
    );
    expect(fakeRes.sendFile).toHaveBeenCalledWith(
      expect.stringMatching(/msgs[/\\]abc\.bin/),
      { headers: { 'Cache-Control': 'private, max-age=31536000, immutable' } },
    );
    // @nestjs/throttler stores per-throttler-name metadata as `<key><name>`.
    const throttle: unknown = Reflect.getMetadata(
      'THROTTLER:TTLdefault',
      controllerMethod('serveMsgs'),
    );
    const limit: unknown = Reflect.getMetadata(
      'THROTTLER:LIMITdefault',
      controllerMethod('serveMsgs'),
    );
    // A media-heavy chat open is dozens of blob fetches within seconds.
    expect({ ttlMs: throttle, limit }).toEqual({ ttlMs: 60000, limit: 600 });
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
