import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { KeyBundlesService, KeyBundleData } from './key-bundles.service';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';
import { IdentityChangeAudit } from './identity-change-audit.entity';
import { IdentityResetService } from './identity-reset.service';

describe('KeyBundlesService', () => {
  let service: KeyBundlesService;
  let keyBundleRepo: Record<string, jest.Mock>;
  let otpRepo: Record<string, jest.Mock>;
  let auditRepo: Record<string, jest.Mock>;
  let identityResetService: Record<string, jest.Mock>;
  // Chainable query-builder mock for the stale-OTP purge in upsertKeyBundle.
  let purgeBuilder: {
    delete: jest.Mock;
    where: jest.Mock;
    andWhere: jest.Mock;
    execute: jest.Mock;
  };

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

    purgeBuilder = {
      delete: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      execute: jest.fn().mockResolvedValue({ affected: 0 }),
    };

    otpRepo = {
      findOne: jest.fn(),
      create: jest.fn(),
      save: jest.fn(),
      upsert: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
      query: jest.fn().mockResolvedValue([[], 0]),
      createQueryBuilder: jest.fn(() => purgeBuilder),
    };

    auditRepo = {
      insert: jest.fn().mockResolvedValue({ identifiers: [{ id: 1 }] }),
    };

    // Default: no completed reset ceremony exists, so an unsigned identity
    // replacement is refused. Tests that model a LEGITIMATE replacement opt in
    // explicitly, which keeps the locked case the default everywhere.
    identityResetService = {
      consumeCompletedReset: jest.fn().mockResolvedValue(false),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        KeyBundlesService,
        { provide: getRepositoryToken(KeyBundle), useValue: keyBundleRepo },
        { provide: getRepositoryToken(OneTimePreKey), useValue: otpRepo },
        {
          provide: getRepositoryToken(IdentityChangeAudit),
          useValue: auditRepo,
        },
        {
          provide: IdentityResetService,
          useValue: identityResetService,
        },
      ],
    }).compile();

    service = module.get<KeyBundlesService>(KeyBundlesService);
    jest.clearAllMocks();
  });

  describe('hasKeyBundle', () => {
    it.each([
      [{ id: 1 }, true],
      [null, false],
    ])(
      'returns %s existence without touching one-time pre-keys',
      async (bundle, expected) => {
        keyBundleRepo.findOne.mockResolvedValue(bundle);

        await expect(service.hasKeyBundle(1)).resolves.toBe(expected);

        expect(keyBundleRepo.findOne).toHaveBeenCalledWith({
          where: { userId: 1 },
        });
        expect(otpRepo.query).not.toHaveBeenCalled();
      },
    );
  });

  describe('upsertKeyBundle', () => {
    it('upserts the key bundle atomically (insert-or-update)', async () => {
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });

      await service.upsertKeyBundle(1, mockKeyBundleData);

      expect(keyBundleRepo.upsert).toHaveBeenCalledWith(
        { userId: 1, ...mockKeyBundleData },
        { conflictPaths: ['userId'] },
      );
      expect(keyBundleRepo.save).not.toHaveBeenCalled();
    });

    it('warns, writes a durable audit row, and reports the churn when an upload replaces an existing identity', async () => {
      const oldIdentity = 'old-identity-public-key-material';
      const newIdentity = 'new-identity-public-key-material';
      keyBundleRepo.findOne.mockResolvedValue({
        userId: 9,
        ...mockKeyBundleData,
        identityPublicKey: oldIdentity,
      });
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });
      // Authorized by a completed reset ceremony (§6.2) — the legitimate path
      // for someone who lost their device keys.
      identityResetService.consumeCompletedReset.mockResolvedValue(true);
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);

      const result = await service.upsertKeyBundle(9, {
        ...mockKeyBundleData,
        identityPublicKey: newIdentity,
      });

      expect(warnSpy).toHaveBeenCalledTimes(1);
      expect(warnSpy).toHaveBeenCalledWith(
        '[identity-churn] userId=9 oldIdentityPrefix=old-identity newIdentityPrefix=new-identity',
      );
      // Phase 0a: the churn is durable — a full audit row, not just a log line.
      expect(auditRepo.insert).toHaveBeenCalledTimes(1);
      expect(auditRepo.insert).toHaveBeenCalledWith({
        userId: 9,
        previousIdentityPublicKey: oldIdentity,
        newIdentityPublicKey: newIdentity,
      });
      expect(result).toEqual({
        identityChanged: true,
        previousIdentityPublicKey: oldIdentity,
      });
      warnSpy.mockRestore();
    });

    it('an audit-row insert failure never fails the upload (loud log, upload acked)', async () => {
      keyBundleRepo.findOne.mockResolvedValue({
        userId: 9,
        ...mockKeyBundleData,
        identityPublicKey: 'old-identity',
      });
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });
      identityResetService.consumeCompletedReset.mockResolvedValue(true);
      auditRepo.insert.mockRejectedValue(new Error('db down'));
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);
      const errorSpy = jest
        .spyOn(Logger.prototype, 'error')
        .mockImplementation(() => undefined);

      const result = await service.upsertKeyBundle(9, {
        ...mockKeyBundleData,
        identityPublicKey: 'new-identity',
      });

      expect(result.identityChanged).toBe(true);
      expect(errorSpy).toHaveBeenCalled();
      warnSpy.mockRestore();
      errorSpy.mockRestore();
    });

    it('does not warn or audit when an upload retains the existing identity', async () => {
      keyBundleRepo.findOne.mockResolvedValue({
        userId: 10,
        ...mockKeyBundleData,
      });
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);

      await service.upsertKeyBundle(10, mockKeyBundleData);

      expect(warnSpy).not.toHaveBeenCalled();
      // Same-identity re-upload (the normal every-connect path) stays silent.
      expect(auditRepo.insert).not.toHaveBeenCalled();
      warnSpy.mockRestore();
    });

    it('does not audit a first-time bundle upload (no prior identity)', async () => {
      keyBundleRepo.findOne.mockResolvedValue(null);
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });

      const result = await service.upsertKeyBundle(7, mockKeyBundleData);

      expect(auditRepo.insert).not.toHaveBeenCalled();
      expect(result).toEqual({
        identityChanged: false,
        previousIdentityPublicKey: null,
      });
    });

    it('purges unused OTPs from superseded identity epochs (durable stale-OTP fix)', async () => {
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });

      await service.upsertKeyBundle(42, mockKeyBundleData);

      // A DELETE scoped to this user, unused rows, whose identity is NULL or
      // different from the newly-uploaded identity — never the current epoch.
      expect(otpRepo.createQueryBuilder).toHaveBeenCalledTimes(1);
      expect(purgeBuilder.delete).toHaveBeenCalledTimes(1);
      expect(purgeBuilder.where).toHaveBeenCalledWith('"userId" = :userId', {
        userId: 42,
      });
      const andWhereCalls = purgeBuilder.andWhere.mock.calls.map((c) => c[0]);
      expect(andWhereCalls).toContain('used = false');
      expect(andWhereCalls).toContain(
        '("identityPublicKey" IS NULL OR "identityPublicKey" != :identity)',
      );
      // The identity bound to the purge is the NEW bundle identity.
      const identityCall = purgeBuilder.andWhere.mock.calls.find(
        (c) => c[1] && 'identity' in c[1],
      );
      expect(identityCall?.[1]).toEqual({
        identity: mockKeyBundleData.identityPublicKey,
      });
      expect(purgeBuilder.execute).toHaveBeenCalledTimes(1);
    });
  });

  // Registration lock (multi-device spec §6.1). Before 0b, ANY upload with a
  // valid session could replace the stored identity key — which is what
  // silently redirects every future conversation to different keys. These pin
  // the refusal and both authorized paths.
  describe('registration lock (§6.1)', () => {
    const STORED = 'BdYgkTwp7ZAWQHWKYxQtsMQZxtVQEtVs1Fo63JM3EKJQ';
    const REPLACEMENT = 'BV/AuiEQx2o3p6cfoebDWHomEc5VTzNsyNNcuYxf3BVF';
    // Real client-produced proof: STORED signs REPLACEMENT ‖ 4242 ‖ NONCE.
    const NONCE = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw=';
    const SIGNATURE =
      '+eSga6vQusMMR5gjRe2rk/XQspEwDVXBmFmGy/1iH2P8kBGS+xQ+vE+xTbnzF+3m878LvYXbIooBi4sAmes7hA==';
    const SIGNED_USER_ID = 4242;

    beforeEach(() => {
      keyBundleRepo.findOne.mockResolvedValue({
        userId: SIGNED_USER_ID,
        ...mockKeyBundleData,
        identityPublicKey: STORED,
      });
      keyBundleRepo.upsert.mockResolvedValue({ raw: [] });
    });

    it('refuses an unauthorized identity replacement and writes NOTHING', async () => {
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);

      await expect(
        service.upsertKeyBundle(SIGNED_USER_ID, {
          ...mockKeyBundleData,
          identityPublicKey: REPLACEMENT,
        }),
      ).rejects.toThrow('identity_locked');

      // No bundle written, no OTP epoch purged, no audit row, no alarm state:
      // a refused attempt must leave the account byte-identical.
      expect(keyBundleRepo.upsert).not.toHaveBeenCalled();
      expect(purgeBuilder.execute).not.toHaveBeenCalled();
      expect(auditRepo.insert).not.toHaveBeenCalled();
      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('[identity-lock] REFUSED'),
      );
      warnSpy.mockRestore();
    });

    it('accepts a replacement proven by the previous identity key', async () => {
      const result = await service.upsertKeyBundle(
        SIGNED_USER_ID,
        { ...mockKeyBundleData, identityPublicKey: REPLACEMENT },
        { signature: SIGNATURE, nonce: NONCE },
      );

      expect(result.identityChanged).toBe(true);
      expect(keyBundleRepo.upsert).toHaveBeenCalledTimes(1);
      // A valid signature must NOT burn a reset ceremony.
      expect(identityResetService.consumeCompletedReset).not.toHaveBeenCalled();
    });

    it('refuses when the signature is valid but for a different account', async () => {
      await expect(
        service.upsertKeyBundle(
          SIGNED_USER_ID + 1,
          { ...mockKeyBundleData, identityPublicKey: REPLACEMENT },
          { signature: SIGNATURE, nonce: NONCE },
        ),
      ).rejects.toThrow('identity_locked');
      expect(keyBundleRepo.upsert).not.toHaveBeenCalled();
    });

    it('refuses when the nonce does not match the signed one', async () => {
      await expect(
        service.upsertKeyBundle(
          SIGNED_USER_ID,
          { ...mockKeyBundleData, identityPublicKey: REPLACEMENT },
          {
            signature: SIGNATURE,
            nonce: Buffer.alloc(32, 1).toString('base64'),
          },
        ),
      ).rejects.toThrow('identity_locked');
    });

    it('falls back to a completed reset ceremony when the signature is unusable', async () => {
      identityResetService.consumeCompletedReset.mockResolvedValue(true);

      const result = await service.upsertKeyBundle(
        SIGNED_USER_ID,
        { ...mockKeyBundleData, identityPublicKey: REPLACEMENT },
        { signature: 'not-a-signature', nonce: NONCE },
      );

      expect(result.identityChanged).toBe(true);
      expect(identityResetService.consumeCompletedReset).toHaveBeenCalledWith(
        SIGNED_USER_ID,
      );
    });

    it('never consults the ceremony for a same-identity re-upload', async () => {
      await service.upsertKeyBundle(SIGNED_USER_ID, {
        ...mockKeyBundleData,
        identityPublicKey: STORED,
      });

      expect(identityResetService.consumeCompletedReset).not.toHaveBeenCalled();
      expect(keyBundleRepo.upsert).toHaveBeenCalledTimes(1);
    });

    it('never consults the ceremony for a first-ever upload', async () => {
      keyBundleRepo.findOne.mockResolvedValue(null);

      await service.upsertKeyBundle(SIGNED_USER_ID, mockKeyBundleData);

      expect(identityResetService.consumeCompletedReset).not.toHaveBeenCalled();
      expect(keyBundleRepo.upsert).toHaveBeenCalledTimes(1);
    });
  });

  describe('uploadOneTimePreKeys', () => {
    const keys = [
      { keyId: 0, publicKey: 'pk-0' },
      { keyId: 1, publicKey: 'pk-1' },
    ];

    it('upserts on (userId,keyId) and tags rows with the explicit identity', async () => {
      otpRepo.upsert.mockResolvedValue({ raw: [] });

      await service.uploadOneTimePreKeys(5, keys, 'epoch-2-identity');

      // No bundle lookup needed — the client supplied the identity tag.
      expect(keyBundleRepo.findOne).not.toHaveBeenCalled();
      expect(otpRepo.save).not.toHaveBeenCalled();
      expect(otpRepo.upsert).toHaveBeenCalledWith(
        [
          {
            userId: 5,
            keyId: 0,
            publicKey: 'pk-0',
            identityPublicKey: 'epoch-2-identity',
            used: false,
          },
          {
            userId: 5,
            keyId: 1,
            publicKey: 'pk-1',
            identityPublicKey: 'epoch-2-identity',
            used: false,
          },
        ],
        { conflictPaths: ['userId', 'keyId'] },
      );
    });

    it('rejects untagged OTP uploads instead of inferring the current identity epoch', async () => {
      keyBundleRepo.findOne.mockResolvedValue({
        userId: 5,
        ...mockKeyBundleData,
      });

      await expect(service.uploadOneTimePreKeys(5, keys)).rejects.toMatchObject(
        {
          message: 'identity_epoch_required',
        },
      );

      expect(otpRepo.upsert).not.toHaveBeenCalled();
    });

    it('preserves existing valid current-epoch rows when rejecting a legacy upload', async () => {
      // A legacy (untagged) upload must be rejected WITHOUT touching any
      // existing rows: no destructive delete/purge and no upsert may run,
      // so previously-stored current-epoch OTPs survive intact.
      await expect(service.uploadOneTimePreKeys(5, keys)).rejects.toThrow(
        'identity_epoch_required',
      );
      expect(otpRepo.upsert).not.toHaveBeenCalled();
      expect(otpRepo.delete).not.toHaveBeenCalled();
      expect(otpRepo.createQueryBuilder).not.toHaveBeenCalled();
    });
  });

  describe('fetchPreKeyBundle', () => {
    const bundle = { id: 1, userId: 5, ...mockKeyBundleData };

    it('returns null when no key bundle exists', async () => {
      keyBundleRepo.findOne.mockResolvedValue(null);

      const result = await service.fetchPreKeyBundle(99);

      expect(result).toBeNull();
      expect(otpRepo.query).not.toHaveBeenCalled();
    });

    it('claims an OTP filtered by the CURRENT identity epoch ($1 user, $2 identity)', async () => {
      keyBundleRepo.findOne.mockResolvedValue(bundle);
      // Real Postgres shape for UPDATE ... RETURNING: [rows, rowCount].
      otpRepo.query.mockResolvedValue([
        [{ id: 10, keyId: 7, publicKey: 'otp-pk-7' }],
        1,
      ]);

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
      // The load-bearing guard: SQL filters on identityPublicKey and binds the
      // current bundle identity as the second parameter.
      const [sql, params] = otpRepo.query.mock.calls[0];
      expect(sql).toContain('UPDATE one_time_pre_keys');
      expect(sql).toContain('"identityPublicKey" = $2');
      expect(params).toEqual([5, mockKeyBundleData.identityPublicKey]);
    });

    it('returns null OTP fields when the current epoch has no unused pre-keys', async () => {
      keyBundleRepo.findOne.mockResolvedValue(bundle);
      otpRepo.query.mockResolvedValue([[], 0]);

      const result = await service.fetchPreKeyBundle(5);

      expect(result?.oneTimePreKeyId).toBeNull();
      expect(result?.oneTimePreKeyPublic).toBeNull();
      // OTP-less bundle is still valid — X3DH completes without a one-time key.
      expect(result?.identityPublicKey).toBe(
        mockKeyBundleData.identityPublicKey,
      );
    });
  });

  describe('countUnusedPreKeys', () => {
    it('counts only unused OTPs of the CURRENT identity epoch', async () => {
      keyBundleRepo.findOne.mockResolvedValue({
        userId: 5,
        ...mockKeyBundleData,
      });
      otpRepo.count.mockResolvedValue(15);

      const count = await service.countUnusedPreKeys(5);

      expect(count).toBe(15);
      expect(otpRepo.count).toHaveBeenCalledWith({
        where: {
          userId: 5,
          used: false,
          identityPublicKey: mockKeyBundleData.identityPublicKey,
        },
      });
    });

    it('returns 0 when the user has no key bundle', async () => {
      keyBundleRepo.findOne.mockResolvedValue(null);

      const count = await service.countUnusedPreKeys(5);

      expect(count).toBe(0);
      expect(otpRepo.count).not.toHaveBeenCalled();
    });
  });

  describe('deleteByUserId', () => {
    it('deletes all OTPs and key bundles for the user', async () => {
      otpRepo.delete.mockResolvedValue({ affected: 10 });
      keyBundleRepo.delete.mockResolvedValue({ affected: 1 });

      await service.deleteByUserId(5);

      expect(otpRepo.delete).toHaveBeenCalledWith({ userId: 5 });
      expect(keyBundleRepo.delete).toHaveBeenCalledWith({ userId: 5 });
    });

    it('deletes OTPs before key bundles', async () => {
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
