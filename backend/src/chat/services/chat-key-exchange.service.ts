import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { KeyBundlesService } from '../../key-bundles/key-bundles.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { PushNotificationsService } from '../../push-notifications/push-notifications.service';
import { validateDto } from '../utils/dto.validator';
import { UploadKeyBundleDto } from '../dto/upload-key-bundle.dto';
import { UploadOneTimePreKeysDto } from '../dto/upload-one-time-pre-keys.dto';
import { FetchPreKeyBundleDto } from '../dto/fetch-pre-key-bundle.dto';
import { RequestSessionRebuildDto } from '../dto/request-session-rebuild.dto';
import { userRoom } from '../utils/user-room';

const PRE_KEY_LOW_THRESHOLD = 10;
const PRE_KEY_FETCH_MIN_INTERVAL_MS = 750;
const PRE_KEY_FETCH_MAP_TTL_MS = 10 * 60 * 1000;
const PRE_KEY_FETCH_MAP_MAX_ENTRIES = 10000;
const SESSION_REBUILD_REQUEST_TTL_MS = 24 * 60 * 60 * 1000;
const SESSION_REBUILD_MAP_MAX_RECIPIENTS = 10000;

@Injectable()
export class ChatKeyExchangeService {
  private readonly logger = new Logger(ChatKeyExchangeService.name);
  private readonly lastPreKeyFetchByPair = new Map<string, number>();
  private readonly pendingSessionRebuildsByRecipient = new Map<
    number,
    Map<number, number>
  >();

  constructor(
    private readonly keyBundlesService: KeyBundlesService,
    private readonly conversationsService: ConversationsService,
    private readonly pushNotificationsService: PushNotificationsService,
  ) {}

  async handleUploadKeyBundle(
    client: Socket,
    data: unknown,
    server: Server,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(UploadKeyBundleDto, data);
      const result = await this.keyBundlesService.upsertKeyBundle(userId, {
        registrationId: dto.registrationId,
        identityPublicKey: dto.identityPublicKey,
        signedPreKeyId: dto.signedPreKeyId,
        signedPreKeyPublic: dto.signedPreKeyPublic,
        signedPreKeySignature: dto.signedPreKeySignature,
      });
      client.emit('keyBundleUploaded', { success: true });
      if (result.identityChanged) {
        // Fire-and-forget: the alarm must never fail or delay the upload ack.
        void this.notifyIdentityChanged(client, userId, server);
      }
    } catch (error) {
      this.logger.error(
        `uploadKeyBundle failed userId=${userId}: ${error.message}`,
      );
      client.emit('error', {
        message: error?.message || 'Failed to upload key bundle',
      });
    }
  }

  /**
   * Phase 0a takeover alarm (multi-device spec §6.0). After a key-bundle
   * upload REPLACED the stored identity:
   * 1. `ownIdentityReplaced` to the account's OTHER live sessions
   *    (`client.to(room)` excludes the uploading socket — it caused the event).
   * 2. Content-free push to every registered endpoint (offline sessions).
   * 3. `peerIdentityChanged` to every conversation peer's room, feeding the
   *    in-conversation timeline row (owner-ratified 2026-08-17).
   * Wording rule: clients render this as "new device/browser sign-in" — the
   * same branch fires on every legitimate reinstall/migration, not just
   * takeover. Same-identity re-uploads (the every-connect path) never reach
   * here: upsertKeyBundle only reports identityChanged on a differing key.
   */
  private async notifyIdentityChanged(
    client: Socket,
    userId: number,
    server: Server,
  ): Promise<void> {
    const occurredAt = new Date().toISOString();
    try {
      client.to(userRoom(userId)).emit('ownIdentityReplaced', { occurredAt });
      const pushPromise = this.pushNotificationsService
        .notifyIdentityChanged(userId)
        .catch(() => this.logger.warn('identity-changed push failed'));
      const conversations = await this.conversationsService.findByUser(userId);
      const peerIds = new Set<number>();
      for (const conv of conversations) {
        const peerId =
          conv.userOne?.id === userId ? conv.userTwo?.id : conv.userOne?.id;
        if (peerId != null && peerId !== userId) peerIds.add(peerId);
      }
      for (const peerId of peerIds) {
        server
          .to(userRoom(peerId))
          .emit('peerIdentityChanged', { userId, occurredAt });
      }
      await pushPromise;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(
        `identity-changed notify failed userId=${userId}: ${message}`,
      );
    }
  }

  async handleUploadOneTimePreKeys(client: Socket, data: any): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(UploadOneTimePreKeysDto, data);
      await this.keyBundlesService.uploadOneTimePreKeys(
        userId,
        dto.keys,
        dto.identityPublicKey,
      );
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

  /**
   * Answers only whether the authenticated caller already has a public bundle.
   * This deliberately does not fetch a bundle: fetchPreKeyBundle consumes an
   * one-time pre-key.
   */
  async handleCheckOwnKeyBundle(client: Socket): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const exists = await this.keyBundlesService.hasKeyBundle(userId);
      client.emit('ownKeyBundleStatus', { exists });
    } catch (error) {
      // Silence is fail-closed on the client: it treats no status as UNKNOWN.
      this.logger.error(
        `checkOwnKeyBundle failed userId=${userId}: ${error.message}`,
      );
    }
  }

  async handleFetchPreKeyBundle(
    client: Socket,
    data: any,
    server: Server,
  ): Promise<void> {
    const requesterId: number = client.data.user?.id;
    if (!requesterId) return;

    try {
      const dto = validateDto(FetchPreKeyBundleDto, data);
      if (this.isPreKeyFetchRateLimited(requesterId, dto.userId)) {
        client.emit('error', {
          message:
            'Pre-key bundle fetch rate limit exceeded. Please retry shortly.',
        });
        return;
      }
      const bundle = await this.keyBundlesService.fetchPreKeyBundle(dto.userId);
      if (bundle) {
        this.clearPendingSessionRebuildRequest(requesterId, dto.userId);
      }

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
          server.to(userRoom(dto.userId)).emit('preKeysLow', { remaining });
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
    if (
      lastSeen !== undefined &&
      now - lastSeen < PRE_KEY_FETCH_MIN_INTERVAL_MS
    ) {
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
    const toDelete =
      this.lastPreKeyFetchByPair.size - PRE_KEY_FETCH_MAP_MAX_ENTRIES;
    for (let i = 0; i < toDelete; i++) {
      this.lastPreKeyFetchByPair.delete(ordered[i][0]);
    }
  }

  deliverPendingSessionRebuilds(client: Socket): void {
    const recipientId: number = client.data.user?.id;
    if (!recipientId) return;
    const pending = this.pendingSessionRebuildsByRecipient.get(recipientId);
    if (!pending) return;

    const now = Date.now();
    for (const [fromUserId, requestedAt] of pending.entries()) {
      if (now - requestedAt > SESSION_REBUILD_REQUEST_TTL_MS) {
        pending.delete(fromUserId);
        continue;
      }
      client.emit('sessionRebuildNeeded', { fromUserId });
    }
    if (pending.size === 0) {
      this.pendingSessionRebuildsByRecipient.delete(recipientId);
    }
  }

  private rememberSessionRebuildRequest(
    recipientId: number,
    requesterId: number,
  ): void {
    this.cleanupPendingSessionRebuilds(Date.now());
    let pending = this.pendingSessionRebuildsByRecipient.get(recipientId);
    if (!pending) {
      pending = new Map<number, number>();
      this.pendingSessionRebuildsByRecipient.set(recipientId, pending);
    }
    pending.set(requesterId, Date.now());
  }

  private clearPendingSessionRebuildRequest(
    recipientId: number,
    requesterId: number,
  ): void {
    const pending = this.pendingSessionRebuildsByRecipient.get(recipientId);
    if (!pending) return;
    pending.delete(requesterId);
    if (pending.size === 0) {
      this.pendingSessionRebuildsByRecipient.delete(recipientId);
    }
  }

  private cleanupPendingSessionRebuilds(now: number): void {
    for (const [recipientId, pending] of this
      .pendingSessionRebuildsByRecipient) {
      for (const [requesterId, requestedAt] of pending) {
        if (now - requestedAt > SESSION_REBUILD_REQUEST_TTL_MS) {
          pending.delete(requesterId);
        }
      }
      if (pending.size === 0) {
        this.pendingSessionRebuildsByRecipient.delete(recipientId);
      }
    }
    // Bound memory the same way the prekey-fetch tracker is bounded: a client
    // can mint pending entries for arbitrary recipientIds (DTO only checks
    // positive), so evict the least-recently-requested recipients past the cap.
    if (
      this.pendingSessionRebuildsByRecipient.size <=
      SESSION_REBUILD_MAP_MAX_RECIPIENTS
    ) {
      return;
    }
    const newest = (pending: Map<number, number>): number =>
      Math.max(...pending.values());
    const ordered = [...this.pendingSessionRebuildsByRecipient.entries()].sort(
      (a, b) => newest(a[1]) - newest(b[1]),
    );
    const toDelete =
      this.pendingSessionRebuildsByRecipient.size -
      SESSION_REBUILD_MAP_MAX_RECIPIENTS;
    for (let i = 0; i < toDelete; i++) {
      this.pendingSessionRebuildsByRecipient.delete(ordered[i][0]);
    }
  }

  /// Relay a session-rebuild request to every live socket for the target user.
  /// Called when receiver cannot decrypt an inbound message — asks sender to
  /// build over their stale session so their next send uses a fresh PreKeySignalMessage.
  async handleRequestSessionRebuild(
    client: Socket,
    data: any,
    server: Server,
  ): Promise<void> {
    const requesterId: number = client.data.user?.id;
    if (!requesterId) return;

    try {
      const dto = validateDto(RequestSessionRebuildDto, data);
      this.rememberSessionRebuildRequest(dto.recipientId, requesterId);
      server.to(userRoom(dto.recipientId)).emit('sessionRebuildNeeded', {
        fromUserId: requesterId,
      });
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
