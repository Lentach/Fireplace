import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { KeyBundlesService } from '../../key-bundles/key-bundles.service';
import { validateDto } from '../utils/dto.validator';
import { UploadKeyBundleDto } from '../dto/upload-key-bundle.dto';
import { UploadOneTimePreKeysDto } from '../dto/upload-one-time-pre-keys.dto';
import { FetchPreKeyBundleDto } from '../dto/fetch-pre-key-bundle.dto';

const PRE_KEY_LOW_THRESHOLD = 10;

@Injectable()
export class ChatKeyExchangeService {
  private readonly logger = new Logger(ChatKeyExchangeService.name);

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
}
