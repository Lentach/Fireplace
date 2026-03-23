import { BadRequestException } from '@nestjs/common';

function startsWith(buf: Buffer, bytes: number[]): boolean {
  return bytes.every((b, i) => buf[i] === b);
}

/**
 * Validates that a buffer is JPEG or PNG by checking magic bytes.
 * Call only for avatar uploads — other media types are encrypted blobs.
 */
export function validateAvatarMagicBytes(buffer: Buffer): void {
  const isJpeg = startsWith(buffer, [0xff, 0xd8, 0xff]);
  const isPng = startsWith(buffer, [0x89, 0x50, 0x4e, 0x47]);
  if (!isJpeg && !isPng) {
    throw new BadRequestException('Avatar must be a JPEG or PNG image.');
  }
}
