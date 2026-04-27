import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { KeyBundlesService } from '../../key-bundles/key-bundles.service';
import { validateDto } from '../utils/dto.validator';
import { UploadKeyBundleDto } from '../dto/upload-key-bundle.dto';
import { UploadOneTimePreKeysDto } from '../dto/upload-one-time-pre-keys.dto';
import { FetchPreKeyBundleDto } from '../dto/fetch-pre-key-bundle.dto';
import { RequestSessionRebuildDto } from '../dto/request-session-rebuild.dto';

const PRE_KEY_LOW_THRESHOLD = 10;
const PRE_KEY_FETCH_MIN_INTERVAL_MS = 750;
const PRE_KEY_FETCH_MAP_TTL_MS = 10 * 60 * 1000;
const PRE_KEY_FETCH_MAP_MAX_ENTRIES = 10000;

@Injectable()
export class ChatKeyExchangeService {
  private readonly logger = new Logger(ChatKeyExchangeService.name);
  private readonly lastPreKeyFetchByPair = new Map<string, number>();

  constructor(private readonly keyBundlesService: KeyBundlesService) {}

  async handleUploadKeyBundle(client: Socket, data: any): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(UploadKeyBundleDto, data);
      await this.keyBundlesService.upsertKeyBundle(userId, {
        registrationId: dto.registrationId,
        identityPublicKey: dto.identityPublicKey,
        signedPreKeyId: dto.signedPreKeyId,
        signedPreKeyPublic: dto.signedPreKeyPublic,
        signedPreKeySignature: dto.signedPreKeySignature,
      });
      client.emit('keyBundleUploaded', { success: true });
    } catch (error) {
      this.logger.error(
        `uploadKeyBundle failed userId=${userId}: ${error.message}`,
      );
      client.emit('error', {
        message: error?.message || 'Failed to upload key bundle',
      });
    }
  }

  async handleUploadOneTimePreKeys(
    client: Socket,
    data: any,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(UploadOneTimePreKeysDto, data);
      await this.keyBundlesService.uploadOneTimePreKeys(userId, dto.keys);
      client.emit('oneTimePreKeysUploaded', { count: dto.keys.length });
    } catch (error) {
      this.logger.error(
        `uploadOneTimePreKeys failed userId=${userId}: ${error.message}`,
      );
      client.emit('error', {
        message: error?.message || 'Failed to upload one-time pre-keys',
      });
    }
  }

  async handleFetchPreKeyBundle(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const requesterId: number = client.data.user?.id;
    if (!requesterId) return;

    try {
      const dto = validateDto(FetchPreKeyBundleDto, data);
      if (this.isPreKeyFetchRateLimited(requesterId, dto.userId)) {
        client.emit('error', {
          message: 'Pre-key bundle fetch rate limit exceeded. Please retry shortly.',
        });
        return;
      }
      const bundle = await this.keyBundlesService.fetchPreKeyBundle(dto.userId);

      client.emit('preKeyBundleResponse', {
        userId: dto.userId,
        bundle,
      });

      // Notify target user to replenish pre-keys if running low
      if (bundle) {
        const remaining = await this.keyBundlesService.countUnusedPreKeys(
          dto.userId,
        );
        if (remaining < PRE_KEY_LOW_THRESHOLD) {
          const targetSocketId = onlineUsers.get(dto.userId);
          if (targetSocketId) {
            server
              .to(targetSocketId)
              .emit('preKeysLow', { remaining });
          }
        }
      }
    } catch (error) {
      this.logger.error(
        `fetchPreKeyBundle failed requesterId=${requesterId}: ${error.message}`,
      );
      client.emit('error', {
        message: error?.message || 'Failed to fetch pre-key bundle',
      });
    }
  }

  private isPreKeyFetchRateLimited(
    requesterId: number,
    recipientId: number,
  ): boolean {
    const now = Date.now();
    this.cleanupPreKeyFetchTracker(now);
    const key = `${requesterId}:${recipientId}`;
    const lastSeen = this.lastPreKeyFetchByPair.get(key);
    if (lastSeen !== undefined && now - lastSeen < PRE_KEY_FETCH_MIN_INTERVAL_MS) {
      return true;
    }
    this.lastPreKeyFetchByPair.set(key, now);
    return false;
  }

  private cleanupPreKeyFetchTracker(now: number): void {
    for (const [key, ts] of this.lastPreKeyFetchByPair.entries()) {
      if (now - ts > PRE_KEY_FETCH_MAP_TTL_MS) {
        this.lastPreKeyFetchByPair.delete(key);
      }
    }
    if (this.lastPreKeyFetchByPair.size <= PRE_KEY_FETCH_MAP_MAX_ENTRIES) {
      return;
    }

    const ordered = [...this.lastPreKeyFetchByPair.entries()].sort(
      (a, b) => a[1] - b[1],
    );
    const toDelete = this.lastPreKeyFetchByPair.size - PRE_KEY_FETCH_MAP_MAX_ENTRIES;
    for (let i = 0; i < toDelete; i++) {
      this.lastPreKeyFetchByPair.delete(ordered[i][0]);
    }
  }

  /// Relay a session-rebuild request to the target user.
  /// Called when receiver cannot decrypt a live message — asks sender to
  /// delete their stale session so their next send uses a fresh PreKeySignalMessage.
  async handleRequestSessionRebuild(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const requesterId: number = client.data.user?.id;
    if (!requesterId) return;

    try {
      const dto = validateDto(RequestSessionRebuildDto, data);
      const targetSocketId = onlineUsers.get(dto.recipientId);
      if (targetSocketId) {
        server.to(targetSocketId).emit('sessionRebuildNeeded', {
          fromUserId: requesterId,
        });
      }
    } catch (error) {
      this.logger.error(
        `requestSessionRebuild failed requesterId=${requesterId}: ${error.message}`,
      );
      client.emit('error', {
        message: error?.message || 'Failed to request session rebuild',
      });
    }
  }
}
