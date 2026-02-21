import { Test, TestingModule } from '@nestjs/testing';
import { ChatKeyExchangeService } from './chat-key-exchange.service';
import {
  KeyBundlesService,
  PreKeyBundleResponse,
} from '../../key-bundles/key-bundles.service';
import { Socket, Server } from 'socket.io';

describe('ChatKeyExchangeService', () => {
  let service: ChatKeyExchangeService;
  let keyBundlesService: jest.Mocked<KeyBundlesService>;

  let mockClient: Partial<Socket>;
  let mockServer: Partial<Server>;
  let onlineUsers: Map<number, string>;

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
    mockClient = {
      data: { user: { id: 1 } },
      emit: jest.fn(),
    };
    mockServer = { to: jest.fn().mockReturnThis(), emit: jest.fn() };
    onlineUsers = new Map();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatKeyExchangeService,
        {
          provide: KeyBundlesService,
          useValue: {
            upsertKeyBundle: jest.fn().mockResolvedValue(undefined),
            uploadOneTimePreKeys: jest.fn().mockResolvedValue(undefined),
            fetchPreKeyBundle: jest.fn(),
            countUnusedPreKeys: jest.fn(),
          },
        },
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
      );

      expect(keyBundlesService.upsertKeyBundle).toHaveBeenCalledWith(1, {
        registrationId: validData.registrationId,
        identityPublicKey: validData.identityPublicKey,
        signedPreKeyId: validData.signedPreKeyId,
        signedPreKeyPublic: validData.signedPreKeyPublic,
        signedPreKeySignature: validData.signedPreKeySignature,
      });
      expect(mockClient.emit).toHaveBeenCalledWith('keyBundleUploaded', {
        success: true,
      });
    });

    it('should emit error when DTO validation fails', async () => {
      const invalidData = { registrationId: -1 };

      await service.handleUploadKeyBundle(
        mockClient as Socket,
        invalidData,
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
      );

      expect(keyBundlesService.upsertKeyBundle).not.toHaveBeenCalled();
      expect(noUserClient.emit).not.toHaveBeenCalled();
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
      await service.handleUploadOneTimePreKeys(
        mockClient as Socket,
        validData,
      );

      expect(keyBundlesService.uploadOneTimePreKeys).toHaveBeenCalledWith(
        1,
        validData.keys,
      );
      expect(mockClient.emit).toHaveBeenCalledWith(
        'oneTimePreKeysUploaded',
        { count: 2 },
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

  describe('handleFetchPreKeyBundle', () => {
    const validData = { userId: 2 };

    it('should call fetchPreKeyBundle and emit preKeyBundleResponse', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(20);

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
        onlineUsers,
      );

      expect(keyBundlesService.fetchPreKeyBundle).toHaveBeenCalledWith(2);
      expect(mockClient.emit).toHaveBeenCalledWith('preKeyBundleResponse', {
        userId: 2,
        bundle: mockBundle,
      });
    });

    it('should emit preKeysLow when remaining count < 10 and target is online', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(5);
      onlineUsers.set(2, 'socket-id-2');

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
        onlineUsers,
      );

      expect(keyBundlesService.countUnusedPreKeys).toHaveBeenCalledWith(2);
      expect(mockServer.to).toHaveBeenCalledWith('socket-id-2');
      expect(mockServer.emit).toHaveBeenCalledWith('preKeysLow', {
        remaining: 5,
      });
    });

    it('should not emit preKeysLow when remaining count >= 10', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(10);
      onlineUsers.set(2, 'socket-id-2');

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
        onlineUsers,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should not emit preKeysLow when target user is offline', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(mockBundle);
      keyBundlesService.countUnusedPreKeys.mockResolvedValue(3);
      // onlineUsers does NOT contain userId 2

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
        onlineUsers,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should not check pre-key count when bundle is null', async () => {
      keyBundlesService.fetchPreKeyBundle.mockResolvedValue(null);

      await service.handleFetchPreKeyBundle(
        mockClient as Socket,
        validData,
        mockServer as Server,
        onlineUsers,
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
        onlineUsers,
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
        onlineUsers,
      );

      expect(keyBundlesService.fetchPreKeyBundle).not.toHaveBeenCalled();
      expect(noUserClient.emit).not.toHaveBeenCalled();
    });
  });
});
