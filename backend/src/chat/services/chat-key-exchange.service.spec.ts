import { Test, TestingModule } from '@nestjs/testing';
import { ChatKeyExchangeService } from './chat-key-exchange.service';
import {
  IdentityLockedError,
  KeyBundlesService,
  PreKeyBundleResponse,
} from '../../key-bundles/key-bundles.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { PushNotificationsService } from '../../push-notifications/push-notifications.service';
import { IdentityResetService } from '../../key-bundles/identity-reset.service';
import { DevicesService } from '../../key-bundles/devices.service';
import { Socket, Server } from 'socket.io';
import { Logger } from '@nestjs/common';

describe('ChatKeyExchangeService', () => {
  let service: ChatKeyExchangeService;
  let keyBundlesService: jest.Mocked<KeyBundlesService>;
  let conversationsService: { findByUser: jest.Mock };
  let pushNotificationsService: {
    notifyIdentityChanged: jest.Mock;
    notifyIdentityReset: jest.Mock;
  };
  let identityResetService: {
    requestReset: jest.Mock;
    cancelReset: jest.Mock;
    getStatusForUser: jest.Mock;
    setRecoveryKey: jest.Mock;
  };
  let devicesService: { isActive: jest.Mock };
  let clientRoomEmit: jest.Mock;

  /** Nonce the registration lock issues onto a socket session (§6.1). */
  interface LockNonce {
    nonce: string;
    expiresAt: number;
  }
  /**
   * The per-socket bag the gateway populates. Declared here so tests can read
   * what the service wrote without asserting a shape at each access.
   */
  interface MockSocketData {
    user: { id: number; deviceId?: number } | null;
    registrationLockNonce?: LockNonce;
  }
  // `Socket.data` is `any`, and `any & T` collapses back to `any` — omit it
  // first so the typed shape actually survives the intersection.
  let mockClient: Omit<Partial<Socket>, 'data'> & { data: MockSocketData };
  let mockServer: Partial<Server>;
  let roomsAdapter: Map<string, Set<string>>;

  const mockBundle: PreKeyBundleResponse = {
    registrationId: 12345,
    identityPublicKey: 'base64-identity-key',
    signedPreKeyId: 1,
    signedPreKeyPublic: 'base64-signed-pre-key',
    signedPreKeySignature: 'base64-signature',
    oneTimePreKeyId: 7,
    oneTimePreKeyPublic: 'otp-pk-7',
  };

  beforeEach(async () => {
    clientRoomEmit = jest.fn();
    mockClient = {
      data: { user: { id: 1 } },
      emit: jest.fn(),
      to: jest.fn().mockReturnValue({ emit: clientRoomEmit }),
    };
    roomsAdapter = new Map<string, Set<string>>();
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
      sockets: {
        adapter: { rooms: roomsAdapter },
        sockets: new Map(),
      } as unknown as Server['sockets'],
    };
    conversationsService = {
      findByUser: jest.fn().mockResolvedValue([]),
    };
    pushNotificationsService = {
      notifyIdentityChanged: jest.fn().mockResolvedValue(undefined),
      notifyIdentityReset: jest.fn().mockResolvedValue(undefined),
    };
    identityResetService = {
      requestReset: jest.fn(),
      cancelReset: jest.fn().mockResolvedValue(false),
      getStatusForUser: jest.fn().mockResolvedValue(null),
      setRecoveryKey: jest.fn().mockResolvedValue(undefined),
    };
    devicesService = {
      isActive: jest.fn().mockResolvedValue(true),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatKeyExchangeService,
        {
          provide: KeyBundlesService,
          useValue: {
            upsertKeyBundle: jest.fn().mockResolvedValue({
              identityChanged: false,
              previousIdentityPublicKey: null,
            }),
            uploadOneTimePreKeys: jest.fn().mockResolvedValue(undefined),
            fetchPreKeyBundle: jest.fn(),
            countUnusedPreKeys: jest.fn(),
            hasKeyBundle: jest.fn(),
            latestIdentityChangeAt: jest.fn().mockResolvedValue(null),
          },
        },
        { provide: ConversationsService, useValue: conversationsService },
        {
          provide: PushNotificationsService,
          useValue: pushNotificationsService,
        },
        { provide: IdentityResetService, useValue: identityResetService },
        { provide: DevicesService, useValue: devicesService },
      ],
    }).compile();

    service = module.get<ChatKeyExchangeService>(ChatKeyExchangeService);
    keyBundlesService = module.get(KeyBundlesService);
    jest.clearAllMocks();
  });

  describe('handleUploadKeyBundle', () => {
    const validData = {
      registrationId: 12345,
      identityPublicKey: 'base64-identity-key',
      signedPreKeyId: 1,
      signedPreKeyPublic: 'base64-signed-pre-key',
      signedPreKeySignature: 'base64-signature',
    };

    it('should call upsertKeyBundle and emit keyBundleUploaded on success', async () => {
      await service.handleUploadKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(keyBundlesService.upsertKeyBundle).toHaveBeenCalledWith(
        1,
        {
          registrationId: validData.registrationId,
          identityPublicKey: validData.identityPublicKey,
          signedPreKeyId: validData.signedPreKeyId,
          signedPreKeyPublic: validData.signedPreKeyPublic,
          signedPreKeySignature: validData.signedPreKeySignature,
        },
        // No registration-lock proof on the normal re-upload path.
        undefined,
        // Device 1: this session's JWT names no other (§8).
        1,
      );
      // The ack tells the uploader whether ITS upload replaced the stored
      // identity, so a device never alarms about its own replacement.
      expect(mockClient.emit).toHaveBeenCalledWith('keyBundleUploaded', {
        success: true,
        identityChanged: false,
      });
      // Same-identity upload (the normal every-connect re-upload): NO alarm.
      await new Promise((resolve) => setImmediate(resolve));
      expect(mockClient.to).not.toHaveBeenCalled();
      expect(
        pushNotificationsService.notifyIdentityChanged,
      ).not.toHaveBeenCalled();
      expect(conversationsService.findByUser).not.toHaveBeenCalled();
    });

    it('should emit error when DTO validation fails', async () => {
      const invalidData = { registrationId: -1 };

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        invalidData,
        mockServer as Server,
      );

      expect(keyBundlesService.upsertKeyBundle).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({
          message: expect.stringContaining('Validation failed'),
        }),
      );
    });

    it('should return early when client has no userId', async () => {
      const noUserClient = { data: { user: null }, emit: jest.fn() };

      await service.handleUploadKeyBundle(
        noUserClient as unknown as Socket,
        validData,
        mockServer as Server,
      );

      expect(keyBundlesService.upsertKeyBundle).not.toHaveBeenCalled();
      expect(noUserClient.emit).not.toHaveBeenCalled();
    });

    // expect.any(String) is typed `any`; the unknown hop keeps the ratchet flat.
    const anyIsoString: unknown = expect.any(String);
    it('identity replacement alarms other sessions, pushes, and flags conversation peers', async () => {
      keyBundlesService.upsertKeyBundle.mockResolvedValue({
        identityChanged: true,
        previousIdentityPublicKey: 'old-identity',
      });
      conversationsService.findByUser.mockResolvedValue([
        { userOne: { id: 1 }, userTwo: { id: 2 } },
        { userOne: { id: 3 }, userTwo: { id: 1 } },
      ]);

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );
      // The alarm is fire-and-forget — drain it.
      await new Promise((resolve) => setImmediate(resolve));

      // Upload is still acked normally.
      expect(mockClient.emit).toHaveBeenCalledWith('keyBundleUploaded', {
        success: true,
        identityChanged: true,
      });
      // Other sessions: client.to(room) EXCLUDES the uploading socket.
      expect(mockClient.to).toHaveBeenCalledWith('user:1');
      expect(clientRoomEmit).toHaveBeenCalledWith(
        'ownIdentityReplaced',
        expect.objectContaining({ occurredAt: anyIsoString }),
      );
      // Offline sessions: content-free push to every endpoint.
      expect(
        pushNotificationsService.notifyIdentityChanged,
      ).toHaveBeenCalledWith(1);
      // Conversation peers get the corroborating event in their rooms.
      expect(mockServer.to).toHaveBeenCalledWith('user:2');
      expect(mockServer.to).toHaveBeenCalledWith('user:3');
      expect(mockServer.to).not.toHaveBeenCalledWith('user:1');
      expect(mockServer.emit).toHaveBeenCalledWith(
        'peerIdentityChanged',
        expect.objectContaining({ userId: 1, occurredAt: anyIsoString }),
      );
    });

    it('a notify failure never breaks the upload ack', async () => {
      keyBundlesService.upsertKeyBundle.mockResolvedValue({
        identityChanged: true,
        previousIdentityPublicKey: 'old-identity',
      });
      conversationsService.findByUser.mockRejectedValue(new Error('db down'));

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );
      await new Promise((resolve) => setImmediate(resolve));

      expect(mockClient.emit).toHaveBeenCalledWith('keyBundleUploaded', {
        success: true,
        identityChanged: true,
      });
      expect(mockClient.emit).not.toHaveBeenCalledWith(
        'error',
        expect.anything(),
      );
    });
  });

  // T3, spec §5.1 / §12 amendment (b): key material may land only on a
  // deviceId a provisioning commit actually activated. Device 1 predates the
  // devices table and stays exempt.
  describe('never-activated deviceId upload rejection', () => {
    const bundleData = {
      registrationId: 12345,
      identityPublicKey: 'base64-identity-key',
      signedPreKeyId: 1,
      signedPreKeyPublic: 'base64-signed-pre-key',
      signedPreKeySignature: 'base64-signature',
    };
    const otpData = { keys: [{ keyId: 1, publicKey: 'pk-1' }] };
    // `jest.Mocked<KeyBundlesService>` members are METHODS to the compiler,
    // so `expect(service.method)` trips unbound-method; this view types the
    // same mock objects as plain function properties for assertions.
    const kbMocks = () =>
      keyBundlesService as unknown as {
        upsertKeyBundle: jest.Mock;
        uploadOneTimePreKeys: jest.Mock;
      };

    it('refuses a bundle from a session on a never-activated deviceId', async () => {
      mockClient.data.user = { id: 1, deviceId: 2 };
      devicesService.isActive.mockResolvedValue(false);

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        bundleData,
        mockServer as Server,
      );

      expect(devicesService.isActive).toHaveBeenCalledWith(1, 2);
      expect(kbMocks().upsertKeyBundle).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('keyBundleUploaded', {
        success: false,
        error: 'device_not_active',
      });
    });

    it('refuses one-time pre-keys the same way, in this handler refusal shape', async () => {
      mockClient.data.user = { id: 1, deviceId: 2 };
      devicesService.isActive.mockResolvedValue(false);

      await service.handleUploadOneTimePreKeys(mockClient as Socket, otpData);

      expect(kbMocks().uploadOneTimePreKeys).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'device_not_active',
      });
    });

    it('a LIVE provisioned device uploads under its own id', async () => {
      mockClient.data.user = { id: 1, deviceId: 2 };
      devicesService.isActive.mockResolvedValue(true);

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        bundleData,
        mockServer as Server,
      );

      expect(kbMocks().upsertKeyBundle).toHaveBeenCalledWith(
        1,
        expect.objectContaining({ registrationId: 12345 }),
        undefined,
        2,
      );
    });

    it('device 1 never consults the activation gate (§8 legacy exemption)', async () => {
      await service.handleUploadKeyBundle(
        mockClient as Socket,
        bundleData,
        mockServer as Server,
      );

      expect(devicesService.isActive).not.toHaveBeenCalled();
      expect(kbMocks().upsertKeyBundle).toHaveBeenCalled();
    });
  });

  describe('handleUploadOneTimePreKeys', () => {
    const validData = {
      keys: [
        { keyId: 1, publicKey: 'pk-1' },
        { keyId: 2, publicKey: 'pk-2' },
      ],
    };

    it('should call uploadOneTimePreKeys and emit oneTimePreKeysUploaded', async () => {
      await service.handleUploadOneTimePreKeys(mockClient as Socket, validData);

      // Legacy payloads remain observable at this boundary, but the key-bundle
      // service must reject them rather than infer an identity epoch.
      expect(keyBundlesService.uploadOneTimePreKeys).toHaveBeenCalledWith(
        1,
        validData.keys,
        undefined,
        1,
      );
      expect(mockClient.emit).toHaveBeenCalledWith('oneTimePreKeysUploaded', {
        count: 2,
      });
    });

    it('forwards the identity epoch tag when a new client supplies it', async () => {
      await service.handleUploadOneTimePreKeys(mockClient as Socket, {
        ...validData,
        identityPublicKey: 'epoch-2-identity',
      });

      expect(keyBundlesService.uploadOneTimePreKeys).toHaveBeenCalledWith(
        1,
        validData.keys,
        'epoch-2-identity',
        1,
      );
    });

    it('should emit error when DTO validation fails', async () => {
      const invalidData = { keys: 'not-an-array' };

      await service.handleUploadOneTimePreKeys(
        mockClient as Socket,
        invalidData,
      );

      expect(keyBundlesService.uploadOneTimePreKeys).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({
          message: expect.stringContaining('Validation failed'),
        }),
      );
    });

    it('reports a lock refusal as identity_locked and logs it as a guard, not a fault', async () => {
      keyBundlesService.uploadOneTimePreKeys.mockRejectedValue(
        new IdentityLockedError(),
      );
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);
      const errorSpy = jest
        .spyOn(Logger.prototype, 'error')
        .mockImplementation(() => undefined);

      await service.handleUploadOneTimePreKeys(mockClient as Socket, validData);

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'identity_locked',
      });
      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('refused by registration lock'),
      );
      expect(errorSpy).not.toHaveBeenCalled();

      warnSpy.mockRestore();
      errorSpy.mockRestore();
    });

    it('should return early when client has no userId', async () => {
      const noUserClient = { data: { user: null }, emit: jest.fn() };

      await service.handleUploadOneTimePreKeys(
        noUserClient as unknown as Socket,
        validData,
      );

      expect(keyBundlesService.uploadOneTimePreKeys).not.toHaveBeenCalled();
      expect(noUserClient.emit).not.toHaveBeenCalled();
    });
  });

  describe('handleCheckOwnKeyBundle', () => {
    it.each([true, false])(
      'returns exists=%s only to the authenticated caller without fetching a pre-key',
      async (exists) => {
        keyBundlesService.hasKeyBundle.mockResolvedValue(exists);

        await service.handleCheckOwnKeyBundle(mockClient as Socket);

        expect(keyBundlesService.hasKeyBundle).toHaveBeenCalledWith(1, 1);
        expect(mockClient.emit).toHaveBeenCalledTimes(1);
        expect(mockClient.emit).toHaveBeenCalledWith('ownKeyBundleStatus', {
          exists,
          // 0b additions: additive, and null when the account is quiet.
          identityReset: null,
          identityReplacedAt: null,
        });
        expect(keyBundlesService.fetchPreKeyBundle).not.toHaveBeenCalled();
      },
    );
  });

  describe('handleFetchPreKeyBundle', () => {
    const validData = { userId: 2 };

    it('should call fetchPreKeyBundle and emit preKeyBundleResponse', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(20);

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(keyBundlesService.fetchPreKeyBundle).toHaveBeenCalledWith(2, 1);
      expect(mockClient.emit).toHaveBeenCalledWith('preKeyBundleResponse', {
        userId: 2,
        bundle: mockBundle,
      });
    });

    // Register socket ids as members of a user's per-user room (one entry
    // per open tab), mirroring `sockets.adapter.rooms` in utils/user-room.ts.
    const joinRoom = (userId: number, ...socketIds: string[]) => {
      roomsAdapter.set(`user:${userId}`, new Set(socketIds));
    };

    it('should emit preKeysLow addressed to the user room when remaining count < 10', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(5);
      joinRoom(2, 'socket-id-2');

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(keyBundlesService.countUnusedPreKeys).toHaveBeenCalledWith(2, 1);
      // BE-007: addressed by room, never a single socket id.
      expect(mockServer.to).toHaveBeenCalledWith('user:2');
      expect(mockServer.to).not.toHaveBeenCalledWith('socket-id-2');
      expect(mockServer.emit).toHaveBeenCalledWith('preKeysLow', {
        remaining: 5,
      });
    });

    it('should reach every open tab with a single room emit (BE-007 multi-tab regression)', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(4);
      // Two tabs for user 2 => two sockets in room `user:2`. The old
      // userId->socketId map kept only the newest socket, so the first tab
      // never learned to replenish its draining prekey pool.
      joinRoom(2, 'socket-tab-a', 'socket-tab-b');

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      // Exactly one room-addressed emit; a real adapter fans it out to both
      // sockets in the room, so BOTH tabs receive preKeysLow.
      expect(mockServer.to).toHaveBeenCalledTimes(1);
      expect(mockServer.to).toHaveBeenCalledWith('user:2');
      expect(roomsAdapter.get('user:2')!.size).toBe(2);
      expect(mockServer.emit).toHaveBeenCalledWith('preKeysLow', {
        remaining: 4,
      });
    });

    it('should not emit preKeysLow when remaining count >= 10', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(10);
      joinRoom(2, 'socket-id-2');

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should still address the user room when no tab is connected (empty-room no-op)', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(3);
      // No sockets in room `user:2`. Emitting to an empty room is a safe
      // no-op, so there is no offline guard: delivery is still by room.

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(mockServer.to).toHaveBeenCalledWith('user:2');
    });

    it('should not check pre-key count when bundle is null', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(null);

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('preKeyBundleResponse', {
        userId: 2,
        bundle: null,
      });
      expect(keyBundlesService.countUnusedPreKeys).not.toHaveBeenCalled();
    });

    it('should emit error when DTO validation fails', async () => {
      const invalidData = { userId: -1 };

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        invalidData,
        mockServer as Server,
      );

      expect(keyBundlesService.fetchPreKeyBundle).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({
          message: expect.stringContaining('Validation failed'),
        }),
      );
    });

    it('should return early when client has no userId', async () => {
      const noUserClient = { data: { user: null }, emit: jest.fn() };

      await service.handleFetchPreKeyBundle(
        noUserClient as unknown as Socket,
        validData,
        mockServer as Server,
      );

      expect(keyBundlesService.fetchPreKeyBundle).not.toHaveBeenCalled();
      expect(noUserClient.emit).not.toHaveBeenCalled();
    });

    it('rate-limits rapid repeated pre-key fetches for same requester-target pair', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(20);

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(keyBundlesService.fetchPreKeyBundle).toHaveBeenCalledTimes(1);
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({
          message:
            'Pre-key bundle fetch rate limit exceeded. Please retry shortly.',
        }),
      );
    });

    it('removes stale pre-key fetch tracker entries during rate-limit checks', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(20);
      const nowSpy = jest.spyOn(Date, 'now').mockReturnValue(1_000_000);
      (service as any).lastPreKeyFetchByPair.set('1:9', 1_000_000 - 700_000); // stale

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      const tracker: Map<string, number> = (service as any)
        .lastPreKeyFetchByPair;
      expect(tracker.has('1:9')).toBe(false);
      nowSpy.mockRestore();
    });
  });

  describe('handleRequestSessionRebuild', () => {
    const validData = { recipientId: 2 };

    it('relays sessionRebuildNeeded to the recipient user room', async () => {
      await service.handleRequestSessionRebuild(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(mockServer.to).toHaveBeenCalledWith('user:2');
      expect(mockServer.emit).toHaveBeenCalledWith('sessionRebuildNeeded', {
        fromUserId: 1,
      });
    });

    it('emits to the recipient room even when the one-socket online map has no entry', async () => {
      await service.handleRequestSessionRebuild(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      expect(mockServer.to).toHaveBeenCalledWith('user:2');
      expect(mockServer.emit).toHaveBeenCalledWith('sessionRebuildNeeded', {
        fromUserId: 1,
      });
    });

    it('replays a pending rebuild request when the recipient connects later', async () => {
      await service.handleRequestSessionRebuild(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      const recipientClient = {
        data: { user: { id: 2 } },
        emit: jest.fn(),
      };
      service.deliverPendingSessionRebuilds(
        recipientClient as unknown as Socket,
      );

      expect(recipientClient.emit).toHaveBeenCalledWith(
        'sessionRebuildNeeded',
        { fromUserId: 1 },
      );
    });

    it('clears a pending rebuild request once the recipient fetches the requester bundle', async () => {
      await service.handleRequestSessionRebuild(
        mockClient as Socket,
        validData,
        mockServer as Server,
      );

      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(20);
      const recipientClient = {
        data: { user: { id: 2 } },
        emit: jest.fn(),
      };
      await service.handleFetchPreKeyBundle(
        recipientClient as unknown as Socket,
        { userId: 1 },
        mockServer as Server,
      );

      (recipientClient.emit as jest.Mock).mockClear();
      service.deliverPendingSessionRebuilds(
        recipientClient as unknown as Socket,
      );

      expect(recipientClient.emit).not.toHaveBeenCalledWith(
        'sessionRebuildNeeded',
        expect.anything(),
      );
    });

    it('emits error when DTO validation fails (invalid recipientId)', async () => {
      await service.handleRequestSessionRebuild(
        mockClient as Socket,
        { recipientId: -1 },
        mockServer as Server,
      );

      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({
          message: expect.stringContaining('Validation failed'),
        }),
      );
    });

    it('returns early when client has no userId', async () => {
      const noUserClient = { data: { user: null }, emit: jest.fn() };

      await service.handleRequestSessionRebuild(
        noUserClient as unknown as Socket,
        validData,
        mockServer as Server,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });
  });

  // Phase 0b: registration lock nonce lifecycle (§6.1).
  describe('registration lock nonce', () => {
    /**
     * The nonce this socket session currently holds. Non-null assertion is the
     * assertion under test: every caller here has just issued one.
     */
    const lockNonce = (): LockNonce => mockClient.data.registrationLockNonce!;

    /** Arguments of the most recent upsertKeyBundle call. */
    const lastUpsertArgs = (): unknown[] => {
      const calls = (keyBundlesService.upsertKeyBundle as unknown as jest.Mock)
        .mock.calls as unknown[][];
      return calls[calls.length - 1];
    };

    const proofPayload = (nonce: string) => ({
      registrationId: 12345,
      identityPublicKey: 'new-identity',
      signedPreKeyId: 1,
      signedPreKeyPublic: 'spk',
      signedPreKeySignature: 'sig',
      identitySignature: 'client-signature',
      nonce,
    });

    it('issues an unpredictable nonce bound to this socket session', () => {
      service.handleGetRegistrationLockNonce(mockClient as Socket);

      const calls = (mockClient.emit as jest.Mock).mock.calls as Array<
        [string, { nonce: string }]
      >;
      const payload = calls.find(
        (call) => call[0] === 'registrationLockNonce',
      )?.[1];
      expect(payload?.nonce).toEqual(expect.any(String));
      expect(Buffer.from(payload?.nonce ?? '', 'base64').length).toBe(32);
      // Held on the socket, so it dies with the connection.
      expect(lockNonce().nonce).toBe(payload?.nonce);
    });

    it('issues a different nonce every time', () => {
      service.handleGetRegistrationLockNonce(mockClient as Socket);
      const first = lockNonce().nonce;
      service.handleGetRegistrationLockNonce(mockClient as Socket);

      expect(lockNonce().nonce).not.toBe(first);
    });

    it('forwards a matching nonce and signature as the upload proof', async () => {
      service.handleGetRegistrationLockNonce(mockClient as Socket);
      const nonce = lockNonce().nonce;

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        proofPayload(nonce),
        mockServer as Server,
      );

      expect(lastUpsertArgs()).toEqual([
        1,
        expect.any(Object),
        { signature: 'client-signature', nonce },
        // Device the session's JWT names (§4); 1 until provisioning ships.
        1,
      ]);
    });

    it('consumes the nonce, so a replay cannot reuse it', async () => {
      service.handleGetRegistrationLockNonce(mockClient as Socket);
      const nonce = lockNonce().nonce;

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        proofPayload(nonce),
        mockServer as Server,
      );
      await service.handleUploadKeyBundle(
        mockClient as Socket,
        proofPayload(nonce),
        mockServer as Server,
      );

      // One nonce buys exactly one attempt.
      expect(lastUpsertArgs()).toEqual([1, expect.any(Object), undefined, 1]);
    });

    it('ignores a nonce never issued to this session', async () => {
      await service.handleUploadKeyBundle(
        mockClient as Socket,
        proofPayload(Buffer.alloc(32, 3).toString('base64')),
        mockServer as Server,
      );

      expect(lastUpsertArgs()).toEqual([1, expect.any(Object), undefined, 1]);
    });

    it('ignores an expired nonce', async () => {
      service.handleGetRegistrationLockNonce(mockClient as Socket);
      const nonce = lockNonce().nonce;
      lockNonce().expiresAt = Date.now() - 1;

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        proofPayload(nonce),
        mockServer as Server,
      );

      expect(lastUpsertArgs()).toEqual([1, expect.any(Object), undefined, 1]);
    });
  });

  describe('refused identity replacement', () => {
    const lockedPayload = {
      registrationId: 12345,
      identityPublicKey: 'unauthorized-identity',
      signedPreKeyId: 1,
      signedPreKeyPublic: 'spk',
      signedPreKeySignature: 'sig',
    };

    beforeEach(() => {
      keyBundlesService.upsertKeyBundle.mockRejectedValue(
        new IdentityLockedError(),
      );
    });

    it('reports the refusal on the upload channel, not as a generic error', async () => {
      await service.handleUploadKeyBundle(
        mockClient as Socket,
        lockedPayload,
        mockServer as Server,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('keyBundleUploaded', {
        success: false,
        error: 'identity_locked',
      });
      expect(mockClient.emit).not.toHaveBeenCalledWith(
        'error',
        expect.anything(),
      );
    });

    it('raises no replacement alarm for an attempt that changed nothing', async () => {
      await service.handleUploadKeyBundle(
        mockClient as Socket,
        lockedPayload,
        mockServer as Server,
      );
      await new Promise((resolve) => setImmediate(resolve));

      expect(mockClient.to).not.toHaveBeenCalled();
      expect(
        pushNotificationsService.notifyIdentityChanged,
      ).not.toHaveBeenCalled();
    });
  });

  // Phase 0b: reset ceremony (§6.2).
  describe('handleResetIdentityRequest', () => {
    it('notifies every session and push endpoint when a ceremony starts', async () => {
      const deadlineAt = new Date(Date.now() + 1000);
      identityResetService.requestReset.mockResolvedValue({
        status: 'pending',
        deadlineAt,
        shortened: false,
      });

      await service.handleResetIdentityRequest(
        mockClient as Socket,
        {},
        mockServer as Server,
      );
      await new Promise((resolve) => setImmediate(resolve));

      expect(mockClient.emit).toHaveBeenCalledWith('identityResetStatus', {
        status: 'pending',
        deadlineAt: deadlineAt.toISOString(),
        shortened: false,
      });
      // Whole room, including the requesting session.
      expect(mockServer.to).toHaveBeenCalledWith('user:1');
      expect(mockServer.emit).toHaveBeenCalledWith('identityResetPending', {
        deadlineAt: deadlineAt.toISOString(),
        shortened: false,
        occurredAt: expect.any(String) as unknown,
      });
      expect(pushNotificationsService.notifyIdentityReset).toHaveBeenCalledWith(
        1,
        'identity_reset_pending',
      );
    });

    it('passes a recovery phrase through and still rings every bell', async () => {
      const deadlineAt = new Date(Date.now() + 1000);
      const phrase =
        'legal winner thank year wave sausage worth useful legal winner thank yellow';
      identityResetService.requestReset.mockResolvedValue({
        status: 'pending',
        deadlineAt,
        shortened: true,
      });

      await service.handleResetIdentityRequest(
        mockClient as Socket,
        { recoveryPhrase: phrase },
        mockServer as Server,
      );
      await new Promise((resolve) => setImmediate(resolve));

      expect(identityResetService.requestReset).toHaveBeenCalledWith(1, phrase);
      // Shortened shortens the delay; it never silences the notifications.
      expect(pushNotificationsService.notifyIdentityReset).toHaveBeenCalledWith(
        1,
        'identity_reset_pending',
      );
      expect(mockServer.emit).toHaveBeenCalledWith(
        'identityResetPending',
        expect.objectContaining({ shortened: true }),
      );
    });

    it.each(['existing', 'cooldown', 'invalid_phrase', 'locked'])(
      're-notifies nobody when the answer is %s',
      async (status) => {
        identityResetService.requestReset.mockResolvedValue({
          status,
          deadlineAt: status === 'existing' ? new Date() : null,
          shortened: false,
        });

        await service.handleResetIdentityRequest(
          mockClient as Socket,
          {},
          mockServer as Server,
        );
        await new Promise((resolve) => setImmediate(resolve));

        expect(mockClient.emit).toHaveBeenCalledWith(
          'identityResetStatus',
          expect.objectContaining({ status }),
        );
        expect(
          pushNotificationsService.notifyIdentityReset,
        ).not.toHaveBeenCalled();
        expect(mockServer.emit).not.toHaveBeenCalledWith(
          'identityResetPending',
          expect.anything(),
        );
      },
    );

    it('rejects a malformed payload without starting anything', async () => {
      await service.handleResetIdentityRequest(
        mockClient as Socket,
        // Over the length cap: the memory-hard verifier must never be handed an
        // unbounded payload. (Scalars are implicitly coerced to strings by
        // validateDto, so a number is NOT a validation failure here.)
        { recoveryPhrase: 'x'.repeat(300) },
        mockServer as Server,
      );

      expect(identityResetService.requestReset).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({ message: expect.any(String) as unknown }),
      );
    });
  });

  describe('handleResetIdentityCancel', () => {
    it('clears every surface and notifies endpoints on a real cancel', async () => {
      identityResetService.cancelReset.mockResolvedValue(true);

      await service.handleResetIdentityCancel(
        mockClient as Socket,
        mockServer as Server,
      );
      await new Promise((resolve) => setImmediate(resolve));

      expect(mockClient.emit).toHaveBeenCalledWith(
        'identityResetCancelResult',
        { cancelled: true },
      );
      expect(mockServer.to).toHaveBeenCalledWith('user:1');
      expect(mockServer.emit).toHaveBeenCalledWith('identityResetCancelled', {
        occurredAt: expect.any(String) as unknown,
      });
      expect(pushNotificationsService.notifyIdentityReset).toHaveBeenCalledWith(
        1,
        'identity_reset_cancelled',
      );
    });

    it('stays silent when there was nothing pending to cancel', async () => {
      identityResetService.cancelReset.mockResolvedValue(false);

      await service.handleResetIdentityCancel(
        mockClient as Socket,
        mockServer as Server,
      );
      await new Promise((resolve) => setImmediate(resolve));

      expect(mockClient.emit).toHaveBeenCalledWith(
        'identityResetCancelResult',
        { cancelled: false },
      );
      expect(mockServer.emit).not.toHaveBeenCalledWith(
        'identityResetCancelled',
        expect.anything(),
      );
      expect(
        pushNotificationsService.notifyIdentityReset,
      ).not.toHaveBeenCalled();
    });
  });

  describe('handleSetRecoveryKey', () => {
    const phrase =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

    it('stores the phrase verifier and confirms', async () => {
      await service.handleSetRecoveryKey(mockClient as Socket, { phrase });

      expect(identityResetService.setRecoveryKey).toHaveBeenCalledWith(
        1,
        phrase,
      );
      expect(mockClient.emit).toHaveBeenCalledWith('recoveryKeySet', {
        success: true,
      });
    });

    it('reports failure without leaking the reason', async () => {
      identityResetService.setRecoveryKey.mockRejectedValue(
        new Error('db down'),
      );

      await service.handleSetRecoveryKey(mockClient as Socket, { phrase });

      expect(mockClient.emit).toHaveBeenCalledWith('recoveryKeySet', {
        success: false,
      });
    });

    it('rejects a too-short phrase', async () => {
      await service.handleSetRecoveryKey(mockClient as Socket, {
        phrase: 'short',
      });

      expect(identityResetService.setRecoveryKey).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('recoveryKeySet', {
        success: false,
      });
    });
  });

  describe('handleCheckOwnKeyBundle (0b additions)', () => {
    it('reports a pending ceremony and the last identity replacement', async () => {
      const deadlineAt = new Date(Date.now() + 1000);
      const replacedAt = new Date(Date.now() - 5000);
      keyBundlesService.hasKeyBundle.mockResolvedValue(true);
      keyBundlesService.latestIdentityChangeAt.mockResolvedValue(replacedAt);
      identityResetService.getStatusForUser.mockResolvedValue({
        status: 'pending',
        deadlineAt,
        shortened: true,
      });

      await service.handleCheckOwnKeyBundle(mockClient as Socket);

      expect(mockClient.emit).toHaveBeenCalledWith('ownKeyBundleStatus', {
        exists: true,
        identityReset: {
          status: 'pending',
          deadlineAt: deadlineAt.toISOString(),
          // Without this a session reconnecting into a 1 h recovery-key
          // ceremony would describe it as the 72 h one.
          shortened: true,
        },
        // This is what gives a session offline at the time its banner.
        identityReplacedAt: replacedAt.toISOString(),
      });
    });

    it('reports nulls when there is no ceremony and no replacement', async () => {
      keyBundlesService.hasKeyBundle.mockResolvedValue(false);

      await service.handleCheckOwnKeyBundle(mockClient as Socket);

      expect(mockClient.emit).toHaveBeenCalledWith('ownKeyBundleStatus', {
        exists: false,
        identityReset: null,
        identityReplacedAt: null,
      });
    });

    it('stays silent on failure so the client keeps treating it as UNKNOWN', async () => {
      keyBundlesService.hasKeyBundle.mockRejectedValue(new Error('db down'));

      await service.handleCheckOwnKeyBundle(mockClient as Socket);

      expect(mockClient.emit).not.toHaveBeenCalledWith(
        'ownKeyBundleStatus',
        expect.anything(),
      );
    });
  });
});
