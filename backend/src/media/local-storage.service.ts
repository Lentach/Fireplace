import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs/promises';
import * as path from 'path';
import { randomUUID } from 'crypto';

export interface UploadAvatarResult {
  secureUrl: string;
  publicId: string;
}
export interface UploadImageResult {
  secureUrl: string;
  publicId: string;
}
export interface UploadVoiceResult {
  secureUrl: string;
  publicId: string;
  duration: number;
}
export interface UploadRawFileResult {
  secureUrl: string;
  publicId: string;
}

@Injectable()
export class LocalStorageService {
  private readonly baseUrl: string;
  private readonly mediaDir: string;

  constructor(private configService: ConfigService) {
    this.baseUrl = configService.get<string>('MEDIA_BASE_URL', 'http://localhost:3000');
    this.mediaDir = configService.get<string>('MEDIA_DIR', '/app/media');
  }

  async uploadAvatar(
    userId: number,
    buffer: Buffer,
    mimeType: string,
  ): Promise<UploadAvatarResult> {
    const ext = mimeType.includes('png') ? 'png' : 'jpg';
    const filename = `${randomUUID()}.${ext}`;
    const publicId = `avatars/${filename}`;
    await fs.mkdir(path.join(this.mediaDir, 'avatars'), { recursive: true });
    await fs.writeFile(path.join(this.mediaDir, publicId), buffer, {
      mode: 0o644,
    });
    return { secureUrl: `${this.baseUrl}/media/${publicId}`, publicId };
  }

  async uploadImage(
    _userId: number,
    buffer: Buffer,
    _mimeType: string,
  ): Promise<UploadImageResult> {
    return this._saveMsgBlob(buffer);
  }

  async uploadVoiceMessage(
    _userId: number,
    buffer: Buffer,
    _mimeType: string,
    duration = 0,
    _expiresIn?: number,
  ): Promise<UploadVoiceResult> {
    const { secureUrl, publicId } = await this._saveMsgBlob(buffer);
    return { secureUrl, publicId, duration };
  }

  async uploadRawFile(
    _userId: number,
    buffer: Buffer,
    _mimeType: string,
    _filename?: string,
  ): Promise<UploadRawFileResult> {
    return this._saveMsgBlob(buffer);
  }

  async deleteAvatar(publicId: string): Promise<void> {
    await this.deleteFile(publicId);
  }

  /** publicId = relative path like 'msgs/abc.bin' or 'avatars/uuid.jpg'.
   *  Full Cloudinary URLs are skipped (legacy messages). ENOENT is silently ignored. */
  async deleteFile(publicId: string): Promise<void> {
    if (publicId.startsWith('http')) return;
    try {
      await fs.unlink(path.join(this.mediaDir, publicId));
    } catch (err: any) {
      if (err?.code !== 'ENOENT') throw err;
    }
  }

  /** Strips baseUrl prefix to get relative path for deleteFile. */
  extractPublicId(mediaUrl: string): string {
    return mediaUrl.replace(`${this.baseUrl}/media/`, '');
  }

  private async _saveMsgBlob(
    buffer: Buffer,
  ): Promise<{ secureUrl: string; publicId: string }> {
    const filename = `${randomUUID()}.bin`;
    const publicId = `msgs/${filename}`;
    await fs.mkdir(path.join(this.mediaDir, 'msgs'), { recursive: true });
    await fs.writeFile(path.join(this.mediaDir, publicId), buffer, {
      mode: 0o644,
    });
    return { secureUrl: `${this.baseUrl}/media/${publicId}`, publicId };
  }
}
