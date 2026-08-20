import { Injectable, Logger } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { Server, Socket } from 'socket.io';
import {
  DEFAULT_DEVICE_ID,
  IdentityLockedError,
  KeyBundlesService,
} from '../../key-bundles/key-bundles.service';
import { IdentityResetService } from '../../key-bundles/identity-reset.service';
import { DevicesService } from '../../key-bundles/devices.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { PushNotificationsService } from '../../push-notifications/push-notifications.service';
import { validateDto } from '../utils/dto.validator';
import { UploadKeyBundleDto } from '../dto/upload-key-bundle.dto';
import {
  ResetIdentityRequestDto,
  SetRecoveryKeyDto,
} from '../dto/identity-reset.dto';
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

/**
 * Lifetime of a registration-lock nonce (§6.1). Short: it only has to survive
 * one client round-trip between asking for it and uploading the signed bundle.
 */
const REGISTRATION_LOCK_NONCE_TTL_MS = 5 * 60 * 1000;
const REGISTRATION_LOCK_NONCE_BYTES = 32;

/** Nonce issued to one authenticated socket session. */
interface RegistrationLockNonce {
  nonce: string;
  expiresAt: number;
}

/** The per-socket bag the gateway populates once a session is authenticated. */
interface AuthenticatedSocketData {
  /**
   * `deviceId` comes from the JWT (Phase 1, spec §4). Absent on a token issued
   * before the claim existed — device 1 by definition (§8).
   */
  user?: { id: number; deviceId?: number };
  registrationLockNonce?: RegistrationLockNonce;
}

/**
 * socket.io declares `Socket.data` as `any`, so every read off it is untyped.
 * One documented narrowing keeps that assertion in a single place instead of
 * repeating it at each access site.
 */
function socketData(client: Socket): AuthenticatedSocketData {
  return client.data as AuthenticatedSocketData;
}

/** Message of an unknown thrown value, without trusting it to be an Error. */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

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
    private readonly identityResetService: IdentityResetService,
    private readonly devicesService: DevicesService,
  ) {}

  /**
   * Issues a single-use nonce for a registration-lock proof (§6.1).
   *
   * Held on the socket itself, so it dies with the session and cannot be
   * replayed from another connection. CSPRNG, never a counter or a timestamp:
   * a predictable nonce would let a proof be prepared in advance.
   */
  handleGetRegistrationLockNonce(client: Socket): void {
    const userId = socketData(client).user?.id;
    if (!userId) return;
    const nonce = randomBytes(REGISTRATION_LOCK_NONCE_BYTES).toString('base64');
    const issued: RegistrationLockNonce = {
      nonce,
      expiresAt: Date.now() + REGISTRATION_LOCK_NONCE_TTL_MS,
    };
    socketData(client).registrationLockNonce = issued;
    client.emit('registrationLockNonce', { nonce });
  }

  /**
   * Takes this session's nonce out of play and returns it only if the echo
   * matches and it has not expired. Single-use: the stored value is cleared on
   * every attempt, valid or not, so one issued nonce authorizes at most one
   * upload attempt.
   */
  private consumeRegistrationLockNonce(
    client: Socket,
    echoed: string | undefined,
  ): string | null {
    const data = socketData(client);
    const issued = data.registrationLockNonce;
    data.registrationLockNonce = undefined;
    if (!issued || !echoed) return null;
    if (issued.expiresAt <= Date.now()) return null;
    if (issued.nonce !== echoed) return null;
    return issued.nonce;
  }

  async handleUploadKeyBundle(
    client: Socket,
    data: unknown,
    server: Server,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(UploadKeyBundleDto, data);
      // Consumed on every attempt, so one issued nonce buys one try.
      const nonce = this.consumeRegistrationLockNonce(client, dto.nonce);
      // The device comes from the SESSION, never from the payload: a
      // bundle belongs to the device whose authenticated socket uploaded
      // it (spec §5.1). A client-named device would let one session
      // scatter key material across namespaces peers later fetch.
      const deviceId = socketData(client).user?.deviceId ?? DEFAULT_DEVICE_ID;
      // Never-activated-id rejection (spec §5.1 / §12 amendment (b)): key
      // material may land only on a device the provisioning commit actually
      // activated. Device 1 predates the devices table and stays exempt.
      if (
        deviceId !== DEFAULT_DEVICE_ID &&
        !(await this.devicesService.isActive(userId, deviceId))
      ) {
        this.logger.warn(
          `uploadKeyBundle refused for never-activated deviceId=${deviceId} userId=${userId}`,
        );
        client.emit('keyBundleUploaded', {
          success: false,
          error: 'device_not_active',
        });
        return;
      }
      const result = await this.keyBundlesService.upsertKeyBundle(
        userId,
        {
          registrationId: dto.registrationId,
          identityPublicKey: dto.identityPublicKey,
          signedPreKeyId: dto.signedPreKeyId,
          signedPreKeyPublic: dto.signedPreKeyPublic,
          signedPreKeySignature: dto.signedPreKeySignature,
        },
        nonce != null && dto.identitySignature != null
          ? { signature: dto.identitySignature, nonce }
          : undefined,
        deviceId,
      );
      // `identityChanged` tells THIS device that its own upload is what
      // replaced the stored identity — and therefore what wrote the audit row
      // it will read back at the next connect. Without it the device that just
      // recovered through the reset ceremony warns its own user that "another
      // sign-in replaced your keys", which trains people to dismiss the one
      // alarm that detects a real takeover. Additive field: an older client
      // ignores it.
      client.emit('keyBundleUploaded', {
        success: true,
        identityChanged: result.identityChanged,
      });
      if (result.identityChanged) {
        // Fire-and-forget: the alarm must never fail or delay the upload ack.
        void this.notifyIdentityChanged(client, userId, server);
      }
    } catch (error) {
      if (error instanceof IdentityLockedError) {
        // Not a failure to report as an error: the lock did its job. The client
        // reads this as "go through the reset ceremony", never as "retry".
        this.logger.warn(
          `uploadKeyBundle refused by registration lock userId=${userId}`,
        );
        client.emit('keyBundleUploaded', {
          success: false,
          error: 'identity_locked',
        });
        return;
      }
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
      // NOTE (open decision, 2026-08-19): the real client emits
      // `uploadKeyBundle` and `uploadOneTimePreKeys` back to back without
      // awaiting either, and the keys are frequently dispatched FIRST — pinned
      // as production reality by `stale_otp_epoch_test.dart:72,76`. The service
      // refuses a tag the account does not publish, so a signature-authorized
      // rotation whose bundle has not landed yet is refused too and starts with
      // an empty pool until the next peer fetch triggers `preKeysLow`. Two
      // order-based rescues were tried and rejected: awaiting this socket's
      // in-flight bundle upload after one macrotask (the trailing frame is
      // dispatched later, so the marker is unset — proven insufficient), and a
      // timed poll for it (makes a lock's verdict depend on wall-clock latency).
      // The real fix is client-side ordering: publish the identity, THEN the
      // keys. Owner decision pending.
      const dto = validateDto(UploadOneTimePreKeysDto, data);
      // Session-bound, like the bundle above.
      const deviceId = socketData(client).user?.deviceId ?? DEFAULT_DEVICE_ID;
      // Never-activated-id rejection (spec §5.1 / §12 amendment (b)), same
      // gate as the bundle; this handler's refusal shape is the error event.
      if (
        deviceId !== DEFAULT_DEVICE_ID &&
        !(await this.devicesService.isActive(userId, deviceId))
      ) {
        this.logger.warn(
          `uploadOneTimePreKeys refused for never-activated deviceId=${deviceId} userId=${userId}`,
        );
        client.emit('error', { message: 'device_not_active' });
        return;
      }
      await this.keyBundlesService.uploadOneTimePreKeys(
        userId,
        dto.keys,
        dto.identityPublicKey,
        deviceId,
      );
      client.emit('oneTimePreKeysUploaded', { count: dto.keys.length });
    } catch (error) {
      if (error instanceof IdentityLockedError) {
        // The lock did its job, so this is not a server fault: the caller's
        // identity is not the one this account publishes. Same vocabulary as
        // the bundle refusal — the route forward is the reset ceremony.
        this.logger.warn(
          `uploadOneTimePreKeys refused by registration lock userId=${userId}`,
        );
      } else {
        this.logger.error(
          `uploadOneTimePreKeys failed userId=${userId}: ${error.message}`,
        );
      }
      client.emit('error', {
        message: error?.message || 'Failed to upload one-time pre-keys',
      });
    }
  }

  /**
   * Answers whether the authenticated caller already has a public bundle, plus
   * the account-protection state a reconnecting session needs to render:
   * an in-flight reset ceremony, and the last identity replacement.
   *
   * This deliberately does not fetch a bundle: fetchPreKeyBundle consumes a
   * one-time pre-key.
   */
  async handleCheckOwnKeyBundle(client: Socket): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      // Per device: this answer gates key generation on the client, and a
      // device that never published its own bundle must not be told one exists
      // just because a sibling device has one.
      const deviceId = socketData(client).user?.deviceId ?? DEFAULT_DEVICE_ID;
      const exists = await this.keyBundlesService.hasKeyBundle(
        userId,
        deviceId,
      );
      // Additive fields: an older client ignores them, and a newer client
      // treats a missing payload as UNKNOWN rather than as "nothing pending".
      const [reset, identityReplacedAt] = await Promise.all([
        this.identityResetService.getStatusForUser(userId),
        this.keyBundlesService.latestIdentityChangeAt(userId),
      ]);
      client.emit('ownKeyBundleStatus', {
        exists,
        identityReset: reset
          ? {
              status: reset.status,
              deadlineAt: reset.deadlineAt.toISOString(),
              // Same flag the live broadcast carries, so a session that
              // reconnects INTO a recovery-key ceremony describes the 1 h
              // wait as 1 h rather than as the default 72 h.
              shortened: reset.shortened,
            }
          : null,
        identityReplacedAt: identityReplacedAt
          ? identityReplacedAt.toISOString()
          : null,
      });
    } catch (error) {
      // Silence is fail-closed on the client: it treats no status as UNKNOWN.
      this.logger.error(
        `checkOwnKeyBundle failed userId=${userId}: ${error.message}`,
      );
    }
  }

  /**
   * Starts an account-identity reset ceremony (§6.2).
   *
   * Reachable with credentials alone, by design: this is the path for someone
   * who genuinely lost their device keys. The protection is not secrecy but
   * TIME plus NOISE — every session and every push endpoint learns immediately,
   * and any one of them can cancel with a single tap for the whole delay.
   */
  async handleResetIdentityRequest(
    client: Socket,
    data: unknown,
    server: Server,
  ): Promise<void> {
    const userId = socketData(client).user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(ResetIdentityRequestDto, data);
      const result = await this.identityResetService.requestReset(
        userId,
        dto.recoveryPhrase,
      );
      client.emit('identityResetStatus', {
        status: result.status,
        deadlineAt: result.deadlineAt
          ? result.deadlineAt.toISOString()
          : undefined,
        shortened: result.shortened,
      });
      // Only a NEW ceremony rings the bells. Re-reporting an existing one to a
      // reconnecting client must not re-notify every device.
      if (result.status === 'pending' && result.deadlineAt) {
        void this.notifyIdentityResetPending(
          userId,
          result.deadlineAt,
          result.shortened,
          server,
        );
      }
    } catch (error) {
      this.logger.error(
        `resetIdentityRequest failed userId=${userId}: ${errorMessage(error)}`,
      );
      client.emit('error', {
        message: errorMessage(error) || 'Failed to start identity reset',
      });
    }
  }

  /**
   * Cancels the pending ceremony (§6.2). No key required — a session that can
   * see the notification must be able to stop it, which is the entire point of
   * the delay.
   */
  async handleResetIdentityCancel(
    client: Socket,
    server: Server,
  ): Promise<void> {
    const userId = socketData(client).user?.id;
    if (!userId) return;

    try {
      const cancelled = await this.identityResetService.cancelReset(userId);
      client.emit('identityResetCancelResult', { cancelled });
      if (cancelled) {
        const occurredAt = new Date().toISOString();
        // Whole room INCLUDING this socket: every surface clears together.
        server
          .to(userRoom(userId))
          .emit('identityResetCancelled', { occurredAt });
        void this.pushNotificationsService
          .notifyIdentityReset(userId, 'identity_reset_cancelled')
          .catch(() => this.logger.warn('identity-reset cancel push failed'));
      }
    } catch (error) {
      this.logger.error(
        `resetIdentityCancel failed userId=${userId}: ${errorMessage(error)}`,
      );
      client.emit('error', {
        message: errorMessage(error) || 'Failed to cancel identity reset',
      });
    }
  }

  /**
   * Announces a newly started ceremony to every session and every registered
   * push endpoint (§6.2). Push is the only channel that reaches a device whose
   * app is closed, which is what makes the delay meaningful.
   */
  private async notifyIdentityResetPending(
    userId: number,
    deadlineAt: Date,
    shortened: boolean,
    server: Server,
  ): Promise<void> {
    const occurredAt = new Date().toISOString();
    try {
      server.to(userRoom(userId)).emit('identityResetPending', {
        deadlineAt: deadlineAt.toISOString(),
        shortened,
        occurredAt,
      });
      await this.pushNotificationsService.notifyIdentityReset(
        userId,
        'identity_reset_pending',
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(
        `identity-reset notify failed userId=${userId}: ${message}`,
      );
    }
  }

  /**
   * Enrolls or replaces the account's recovery phrase (§6.2.1). The phrase is
   * generated and shown on the client; the server keeps only a memory-hard
   * verifier and never returns it.
   */
  async handleSetRecoveryKey(client: Socket, data: unknown): Promise<void> {
    const userId = socketData(client).user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(SetRecoveryKeyDto, data);
      await this.identityResetService.setRecoveryKey(userId, dto.phrase);
      client.emit('recoveryKeySet', { success: true });
    } catch (error) {
      this.logger.error(
        `setRecoveryKey failed userId=${userId}: ${errorMessage(error)}`,
      );
      client.emit('recoveryKeySet', { success: false });
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
      const targetDeviceId = dto.deviceId ?? DEFAULT_DEVICE_ID;
      const bundle = await this.keyBundlesService.fetchPreKeyBundle(
        dto.userId,
        targetDeviceId,
      );
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
          targetDeviceId,
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
