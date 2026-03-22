import { Injectable, Logger, Inject } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as fs from 'fs/promises';
import * as path from 'path';
import { LocalStorageService } from './local-storage.service';
import { Message } from '../messages/message.entity';

@Injectable()
export class MediaCleanupService {
  private readonly logger = new Logger(MediaCleanupService.name);

  constructor(
    private storage: LocalStorageService,
    @InjectRepository(Message) private messageRepo: Repository<Message>,
    @Inject('MEDIA_BASE_URL') private mediaBaseUrl: string,
    @Inject('MEDIA_DIR') private mediaDir: string,
  ) {}

  /** Delete a single media file by its URL. No-op for null or Cloudinary URLs. */
  async deleteMediaFile(mediaUrl: string | null | undefined): Promise<void> {
    if (!mediaUrl) return;
    if (!mediaUrl.startsWith(this.mediaBaseUrl)) return;
    try {
      const publicId = this.storage.extractPublicId(mediaUrl);
      await this.storage.deleteFile(publicId);
    } catch (err) {
      this.logger.warn(`Failed to delete media file ${mediaUrl}: ${err}`);
    }
  }

  /** Cron: daily at 03:00 — delete orphaned and expired files from disk. */
  @Cron('0 3 * * *')
  async cleanupOrphanedFiles(): Promise<void> {
    this.logger.log('Starting media cleanup cron');
    const msgsDir = path.join(this.mediaDir, 'msgs');

    let diskFiles: string[];
    try {
      diskFiles = await fs.readdir(msgsDir);
    } catch {
      this.logger.warn('Media msgs dir not found — skipping cleanup');
      return;
    }

    const validRows: { mediaUrl: string }[] = await this.messageRepo
      .createQueryBuilder('msg')
      .select('msg.mediaUrl', 'mediaUrl')
      .where('msg.mediaUrl IS NOT NULL')
      .andWhere('msg.mediaUrl LIKE :prefix', {
        prefix: `${this.mediaBaseUrl}/media/%`,
      })
      .andWhere('(msg.expiresAt IS NULL OR msg.expiresAt > NOW())')
      .getRawMany();

    const validFilenames = new Set(
      validRows.map((r) => r.mediaUrl.split('/').pop()),
    );

    let deleted = 0;
    for (const file of diskFiles) {
      if (!validFilenames.has(file)) {
        try {
          await fs.unlink(path.join(msgsDir, file));
          deleted++;
        } catch (err) {
          this.logger.warn(`Cron: failed to delete ${file}: ${err}`);
        }
      }
    }
    this.logger.log(`Cron cleanup done: ${deleted} files deleted`);
  }
}
