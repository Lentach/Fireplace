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

  it('consumeAndRotate throws when token unknown', async () => {
    repo.findOne.mockResolvedValue(null);
    await expect(service.consumeAndRotate('unknown')).rejects.toThrow(
      UnauthorizedException,
    );
  });
});
