import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UnauthorizedException } from '@nestjs/common';
import {
  RefreshTokensService,
  REFRESH_TOKEN_TTL_DAYS,
} from './refresh-tokens.service';
import { RefreshToken } from './refresh-token.entity';

describe('RefreshTokensService', () => {
  let service: RefreshTokensService;
  let repo: jest.Mocked<Repository<RefreshToken>>;

  beforeEach(async () => {
    const mockRepo = {
      create: jest.fn((x) => x),
      save: jest.fn(),
      findOne: jest.fn(),
      remove: jest.fn(),
      delete: jest.fn(),
    };

    const module = await Test.createTestingModule({
      providers: [
        RefreshTokensService,
        {
          provide: getRepositoryToken(RefreshToken),
          useValue: mockRepo,
        },
      ],
    }).compile();

    service = module.get(RefreshTokensService);
    repo = module.get(getRepositoryToken(RefreshToken));
    jest.clearAllMocks();
  });

  it('hashToken is deterministic', () => {
    const a = RefreshTokensService.hashToken('plain-one');
    const b = RefreshTokensService.hashToken('plain-one');
    expect(a).toBe(b);
    expect(a.length).toBe(64);
  });

  it('createToken persists hashed token with ~365d expiry', async () => {
    repo.save.mockImplementation(async (e: RefreshToken) => e);

    const plain = await service.createToken(42);

    expect(plain.length).toBeGreaterThan(40);
    expect(repo.save).toHaveBeenCalled();
    const saved = repo.save.mock.calls[0][0] as RefreshToken;
    expect(saved.userId).toBe(42);
    expect(saved.tokenHash).toBe(RefreshTokensService.hashToken(plain));
    const msUntilExpiry = saved.expiresAt.getTime() - Date.now();
    expect(msUntilExpiry).toBeGreaterThan(
      (REFRESH_TOKEN_TTL_DAYS - 2) * 86400 * 1000,
    );
  });

  it('consumeAndSlide throws when token unknown', async () => {
    repo.findOne.mockResolvedValue(null);
    await expect(service.consumeAndSlide('unknown')).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('consumeAndSlide extends the existing refresh token instead of invalidating a lost response retry', async () => {
    const oldExpiry = new Date(Date.now() + 60_000);
    const oldRow = {
      id: 'old-token-id',
      userId: 42,
      tokenHash: RefreshTokensService.hashToken('old-plain'),
      expiresAt: oldExpiry,
    } as RefreshToken;
    repo.findOne.mockResolvedValue(oldRow);
    repo.save.mockImplementation(async (e: RefreshToken) => e);

    const result = await service.consumeAndSlide('old-plain');

    expect(repo.findOne).toHaveBeenCalledWith({
      where: { tokenHash: RefreshTokensService.hashToken('old-plain') },
    });
    expect(repo.remove).not.toHaveBeenCalled();
    expect(repo.save).toHaveBeenCalledWith(oldRow);
    expect(result).toBe(42);
    expect(oldRow.expiresAt.getTime()).toBeGreaterThan(oldExpiry.getTime());
    expect(oldRow.expiresAt.getTime()).toBeGreaterThan(
      Date.now() + (REFRESH_TOKEN_TTL_DAYS - 2) * 86400 * 1000,
    );
  });

  it('consumeAndSlide removes expired tokens and rejects without issuing a replacement', async () => {
    const expiredRow = {
      id: 'expired-token-id',
      userId: 42,
      tokenHash: RefreshTokensService.hashToken('expired-plain'),
      expiresAt: new Date(Date.now() - 1),
    } as RefreshToken;
    repo.findOne.mockResolvedValue(expiredRow);

    await expect(service.consumeAndSlide('expired-plain')).rejects.toThrow(
      new UnauthorizedException('Refresh token expired'),
    );

    expect(repo.remove).toHaveBeenCalledWith(expiredRow);
    expect(repo.save).not.toHaveBeenCalled();
  });

  it('revokeByPlain removes matching tokens and ignores unknown tokens', async () => {
    const row = {
      id: 'token-id',
      userId: 42,
      tokenHash: RefreshTokensService.hashToken('plain-to-revoke'),
      expiresAt: new Date(Date.now() + 60_000),
    } as RefreshToken;
    repo.findOne.mockResolvedValueOnce(row).mockResolvedValueOnce(null);

    await service.revokeByPlain('plain-to-revoke');
    await service.revokeByPlain('unknown-plain');

    expect(repo.findOne).toHaveBeenNthCalledWith(1, {
      where: { tokenHash: RefreshTokensService.hashToken('plain-to-revoke') },
    });
    expect(repo.findOne).toHaveBeenNthCalledWith(2, {
      where: { tokenHash: RefreshTokensService.hashToken('unknown-plain') },
    });
    expect(repo.remove).toHaveBeenCalledTimes(1);
    expect(repo.remove).toHaveBeenCalledWith(row);
  });

  it('revokeAllForUser deletes refresh sessions by userId', async () => {
    await service.revokeAllForUser(42);

    expect(repo.delete).toHaveBeenCalledWith({ userId: 42 });
  });
});
