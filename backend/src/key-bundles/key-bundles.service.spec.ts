import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { KeyBundlesService, KeyBundleData } from './key-bundles.service';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';

describe('KeyBundlesService', () => {
  let service: KeyBundlesService;
  let keyBundleRepo: Record<string, jest.Mock>;
  let otpRepo: Record<string, jest.Mock>;

  const mockKeyBundleData: KeyBundleData = {
    registrationId: 12345,
    identityPublicKey: 'base64-identity-key',
    signedPreKeyId: 1,
    signedPreKeyPublic: 'base64-signed-pre-key',
    signedPreKeySignature: 'base64-signature',
  };

  beforeEach(async () => {
    keyBundleRepo = {
      findOne: jest.fn(),
      create: jest.fn(),
      save: jest.fn(),
      delete: jest.fn(),
      upsert: jest.fn(),
    };

    otpRepo = {
      findOne: jest.fn(),
      create: jest.fn(),
      save: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        KeyBundlesService,
        {
          provide: getRepositoryToken(KeyBundle),
          useValue: keyBundleRepo,
        },
        {
          provide: getRepositoryToken(OneTimePreKey),
          useValue: otpRepo,
        },
      ],
    }).compile();

    service = module.get<KeyBundlesService>(KeyBundlesService);
    jest.clearAllMocks();
  });

  describe('upsertKeyBundle', () => {
    it('should upsert key bundle (atomic insert-or-update)', async () => {
      keyBundleRepo.upsert.mockResolvedValue({ identifiers: [], generatedMaps: [], raw: [] });

      await service.upsertKeyBundle(1, mockKeyBundleData);

      expect(keyBundleRepo.upsert).toHaveBeenCalledWith(
        { userId: 1, ...mockKeyBundleData },
        { conflictPaths: ['userId'] },
      );
      expect(keyBundleRepo.findOne).not.toHaveBeenCalled();
      expect(keyBundleRepo.save).not.toHaveBeenCalled();
    });

    it('should use the same upsert call for both create and update paths', async () => {
      keyBundleRepo.upsert.mockResolvedValue({ identifiers: [], generatedMaps: [], raw: [] });

      await service.upsertKeyBundle(42, mockKeyBundleData);

      expect(keyBundleRepo.upsert).toHaveBeenCalledTimes(1);
      expect(keyBundleRepo.upsert).toHaveBeenCalledWith(
        { userId: 42, ...mockKeyBundleData },
        { conflictPaths: ['userId'] },
      );
    });
  });

  describe('uploadOneTimePreKeys', () => {
    it('should store a batch of one-time pre-keys', async () => {
      const keys = [
        { keyId: 1, publicKey: 'pk-1' },
        { keyId: 2, publicKey: 'pk-2' },
        { keyId: 3, publicKey: 'pk-3' },
      ];

      const entities = keys.map((k) => ({
        userId: 5,
        keyId: k.keyId,
        publicKey: k.publicKey,
      }));
      otpRepo.create
        .mockReturnValueOnce(entities[0])
        .mockReturnValueOnce(entities[1])
        .mockReturnValueOnce(entities[2]);
      otpRepo.save.mockResolvedValue(entities);

      await service.uploadOneTimePreKeys(5, keys);

      expect(otpRepo.create).toHaveBeenCalledTimes(3);
      expect(otpRepo.create).toHaveBeenCalledWith({
        userId: 5,
        keyId: 1,
        publicKey: 'pk-1',
      });
      expect(otpRepo.create).toHaveBeenCalledWith({
        userId: 5,
        keyId: 2,
        publicKey: 'pk-2',
      });
      expect(otpRepo.create).toHaveBeenCalledWith({
        userId: 5,
        keyId: 3,
        publicKey: 'pk-3',
      });
      expect(otpRepo.save).toHaveBeenCalledWith(entities);
    });
  });

  describe('fetchPreKeyBundle', () => {
    it('should return null when no key bundle exists', async () => {
      keyBundleRepo.findOne.mockResolvedValue(null);

      const result = await service.fetchPreKeyBundle(99);

      expect(result).toBeNull();
      expect(otpRepo.findOne).not.toHaveBeenCalled();
    });

    it('should return bundle with one unused OTP and mark it as used', async () => {
      const bundle = {
        id: 1,
        userId: 5,
        ...mockKeyBundleData,
      };
      const otp = { id: 10, userId: 5, keyId: 7, publicKey: 'otp-pk-7', used: false };

      keyBundleRepo.findOne.mockResolvedValue(bundle);
      otpRepo.findOne.mockResolvedValue(otp);
      otpRepo.save.mockResolvedValue({ ...otp, used: true });

      const result = await service.fetchPreKeyBundle(5);

      expect(result).toEqual({
        registrationId: mockKeyBundleData.registrationId,
        identityPublicKey: mockKeyBundleData.identityPublicKey,
        signedPreKeyId: mockKeyBundleData.signedPreKeyId,
        signedPreKeyPublic: mockKeyBundleData.signedPreKeyPublic,
        signedPreKeySignature: mockKeyBundleData.signedPreKeySignature,
        oneTimePreKeyId: 7,
        oneTimePreKeyPublic: 'otp-pk-7',
      });

      expect(otp.used).toBe(true);
      expect(otpRepo.save).toHaveBeenCalledWith(otp);
      expect(otpRepo.findOne).toHaveBeenCalledWith({
        where: { userId: 5, used: false },
        order: { id: 'ASC' },
      });
    });

    it('should return null OTP fields when no unused pre-keys remain', async () => {
      const bundle = {
        id: 1,
        userId: 5,
        ...mockKeyBundleData,
      };

      keyBundleRepo.findOne.mockResolvedValue(bundle);
      otpRepo.findOne.mockResolvedValue(null);

      const result = await service.fetchPreKeyBundle(5);

      expect(result).toEqual({
        registrationId: mockKeyBundleData.registrationId,
        identityPublicKey: mockKeyBundleData.identityPublicKey,
        signedPreKeyId: mockKeyBundleData.signedPreKeyId,
        signedPreKeyPublic: mockKeyBundleData.signedPreKeyPublic,
        signedPreKeySignature: mockKeyBundleData.signedPreKeySignature,
        oneTimePreKeyId: null,
        oneTimePreKeyPublic: null,
      });

      expect(otpRepo.save).not.toHaveBeenCalled();
    });
  });

  describe('countUnusedPreKeys', () => {
    it('should return the count of unused pre-keys for a user', async () => {
      otpRepo.count.mockResolvedValue(15);

      const count = await service.countUnusedPreKeys(5);

      expect(count).toBe(15);
      expect(otpRepo.count).toHaveBeenCalledWith({
        where: { userId: 5, used: false },
      });
    });

    it('should return 0 when no unused pre-keys exist', async () => {
      otpRepo.count.mockResolvedValue(0);

      const count = await service.countUnusedPreKeys(5);

      expect(count).toBe(0);
    });
  });

  describe('deleteByUserId', () => {
    it('should delete all OTPs and key bundles for the user', async () => {
      otpRepo.delete.mockResolvedValue({ affected: 10 });
      keyBundleRepo.delete.mockResolvedValue({ affected: 1 });

      await service.deleteByUserId(5);

      expect(otpRepo.delete).toHaveBeenCalledWith({ userId: 5 });
      expect(keyBundleRepo.delete).toHaveBeenCalledWith({ userId: 5 });
    });

    it('should delete OTPs before key bundles', async () => {
      const callOrder: string[] = [];
      otpRepo.delete.mockImplementation(async () => {
        callOrder.push('otp');
        return { affected: 0 };
      });
      keyBundleRepo.delete.mockImplementation(async () => {
        callOrder.push('keyBundle');
        return { affected: 0 };
      });

      await service.deleteByUserId(5);

      expect(callOrder).toEqual(['otp', 'keyBundle']);
    });
  });
});
