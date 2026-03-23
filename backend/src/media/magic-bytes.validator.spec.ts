import { BadRequestException } from '@nestjs/common';
import { validateAvatarMagicBytes } from './magic-bytes.validator';

describe('validateAvatarMagicBytes', () => {
  it('accepts JPEG', () => {
    expect(() =>
      validateAvatarMagicBytes(Buffer.from([0xff, 0xd8, 0xff, 0xe0])),
    ).not.toThrow();
  });

  it('accepts PNG', () => {
    expect(() =>
      validateAvatarMagicBytes(
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
    ).not.toThrow();
  });

  it('rejects EXE (MZ header)', () => {
    expect(() =>
      validateAvatarMagicBytes(Buffer.from([0x4d, 0x5a, 0x00, 0x00])),
    ).toThrow(BadRequestException);
  });

  it('rejects empty buffer', () => {
    expect(() => validateAvatarMagicBytes(Buffer.alloc(0))).toThrow(
      BadRequestException,
    );
  });

  it('rejects GIF', () => {
    expect(() =>
      validateAvatarMagicBytes(Buffer.from([0x47, 0x49, 0x46, 0x38])),
    ).toThrow(BadRequestException);
  });
});
