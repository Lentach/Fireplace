import { Injectable, Logger, Inject } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as fs from 'fs/promises';
import * as path from 'path';
import { LocalStorageService } from './local-storage.service';
import { Message } from '../messages/message.entity';
import { MESSAGE_NOT_EXPIRED_SQL } from '../messages/message-expiry.util';

/** Per-run cleanup tally (also logged to stdout → docker logs). */
export interface MediaCleanupSummary {
  /** Total files seen in the msgs dir. */
  scanned: number;
  /** Total files unlinked this run. */
  deleted: number;
  /** Deleted files that NO message row references (upload-ok, send-failed gap). */
  orphan: number;
  /** Deleted files referenced by a row that is expired. */
  expired: number;
  /** Unreferenced files left in place because they are newer than the grace window. */
  graceSkipped: number;
}

/**
 * Default grace window: never delete a file written within this many ms. Protects
 * an in-flight upload whose `sendMessage` emit/persist has not landed yet (or is
 * mid-retry) from being swept by a cron run that overlaps the send. Override with
 * the MEDIA_CLEANUP_GRACE_MS env var.
 */
const DEFAULT_GRACE_MS = 15 * 60 * 1000;

function resolveGraceMs(): number {
  const raw = process.env.MEDIA_CLEANUP_GRACE_MS;
  // Treat unset OR empty/whitespace-only as "not configured". A blank
  // MEDIA_CLEANUP_GRACE_MS= (the ordinary docker-compose shape) must NOT
  // collapse through Number('') === 0 and silently disable the in-flight-upload
  // protection — that is the only permanent data-loss path in the media sweep.
  // Only a genuinely numeric, non-negative value overrides the default.
  if (raw == null || raw.trim() === '') return DEFAULT_GRACE_MS;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_GRACE_MS;
}

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
  async cleanupOrphanedFiles(): Promise<MediaCleanupSummary> {
    this.logger.log('Starting media cleanup cron');
    const msgsDir = path.join(this.mediaDir, 'msgs');

    const empty: MediaCleanupSummary = {
      scanned: 0,
      deleted: 0,
      orphan: 0,
      expired: 0,
      graceSkipped: 0,
    };

    let diskFiles: string[];
    try {
      diskFiles = await fs.readdir(msgsDir);
    } catch {
      this.logger.warn('Media msgs dir not found — skipping cleanup');
      return empty;
    }

    // Filenames referenced by a NON-EXPIRED message row — never delete these.
    const validRows: { mediaUrl: string }[] = await this.messageRepo
      .createQueryBuilder('msg')
      .select('msg.mediaUrl', 'mediaUrl')
      .where('msg.mediaUrl IS NOT NULL')
      .andWhere('msg.mediaUrl LIKE :prefix', {
        prefix: `${this.mediaBaseUrl}/media/%`,
      })
      .andWhere(MESSAGE_NOT_EXPIRED_SQL.replace(/\bm\./g, 'msg.'), {
        now: new Date(),
      })
      .getRawMany();

    const validFilenames = new Set(
      validRows.map((r) => r.mediaUrl.split('/').pop()),
    );

    // Filenames referenced by ANY message row (expired or not). Lets us tell a
    // genuine ORPHAN (no row references it at all → upload-ok/send-failed gap)
    // apart from EXPIRED media (a row exists but has expired).
    const referencedRows: { mediaUrl: string }[] = await this.messageRepo
      .createQueryBuilder('msg')
      .select('msg.mediaUrl', 'mediaUrl')
      .where('msg.mediaUrl IS NOT NULL')
      .andWhere('msg.mediaUrl LIKE :prefix', {
        prefix: `${this.mediaBaseUrl}/media/%`,
      })
      .getRawMany();

    const referencedFilenames = new Set(
      referencedRows.map((r) => r.mediaUrl.split('/').pop()),
    );

    const graceMs = resolveGraceMs();
    const nowMs = Date.now();
    const summary: MediaCleanupSummary = {
      scanned: diskFiles.length,
      deleted: 0,
      orphan: 0,
      expired: 0,
      graceSkipped: 0,
    };

    for (const file of diskFiles) {
      if (validFilenames.has(file)) continue; // referenced + live → keep

      const filePath = path.join(msgsDir, file);

      // Grace period: skip files written within the grace window — a recent
      // upload's send emit may still be in flight. Such a file is deleted on a
      // later run once it ages past the window and is still unreferenced.
      //
      // Age is clamped at 0 because mtime can legitimately exceed the nowMs
      // captured before this loop: filesystem timestamp granularity (notably
      // NTFS) rounds a just-written mtime UP, so a raw subtraction goes
      // NEGATIVE and reports an orphan as "fresh" even when graceMs is 0. That
      // made the graceMs=0 spec flaky, and for a file stamped far in the future
      // it leaked the orphan forever. A file cannot be younger than zero.
      try {
        const stat = await fs.stat(filePath);
        if (Math.max(0, nowMs - stat.mtimeMs) < graceMs) {
          summary.graceSkipped++;
          continue;
        }
      } catch (err) {
        this.logger.warn(`Cron: failed to stat ${file}: ${err}`);
        continue;
      }

      try {
        await fs.unlink(filePath);
        summary.deleted++;
        if (referencedFilenames.has(file)) summary.expired++;
        else summary.orphan++;
      } catch (err) {
        this.logger.warn(`Cron: failed to delete ${file}: ${err}`);
      }
    }

    this.logger.log(
      `Cron cleanup done: scanned=${summary.scanned} deleted=${summary.deleted} ` +
        `orphan=${summary.orphan} expired=${summary.expired} ` +
        `graceSkipped=${summary.graceSkipped} (graceMs=${graceMs})`,
    );
    return summary;
  }
}
