import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from './strategies/jwt.strategy';

describe('JwtStrategy.validate', () => {
  let strategy: JwtStrategy;
  const mockUsersService = { findById: jest.fn() };
  const mockConfigService = { get: jest.fn().mockReturnValue('test-secret') };

  beforeEach(() => {
    jest.clearAllMocks();
    strategy = new JwtStrategy(mockUsersService as never, mockConfigService as never);
  });

  it('rejects when user not found', async () => {
    mockUsersService.findById.mockResolvedValue(null);
    await expect(
      strategy.validate({ sub: 1, username: 'a', tag: '1234', iat: 1000 }),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('accepts token issued after passwordChangedAt', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1,
      username: 'a',
      tag: '1234',
      profilePictureUrl: null,
      passwordChangedAt: new Date(900 * 1000),
    });
    const result = await strategy.validate({
      sub: 1,
      username: 'a',
      tag: '1234',
      iat: 1000,
    });
    expect(result.id).toBe(1);
  });

  it('rejects token issued before passwordChangedAt', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1,
      username: 'a',
      tag: '1234',
      profilePictureUrl: null,
      passwordChangedAt: new Date(1000 * 1000),
    });
    await expect(
      strategy.validate({ sub: 1, username: 'a', tag: '1234', iat: 900 }),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('rejects token issued in the same second as passwordChangedAt', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1,
      username: 'a',
      tag: '1234',
      profilePictureUrl: null,
      passwordChangedAt: new Date(1000 * 1000),
    });
    await expect(
      strategy.validate({ sub: 1, username: 'a', tag: '1234', iat: 1000 }),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('accepts when passwordChangedAt is null', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1,
      username: 'a',
      tag: '1234',
      profilePictureUrl: null,
      passwordChangedAt: null,
    });
    const result = await strategy.validate({
      sub: 1,
      username: 'a',
      tag: '1234',
      iat: 1,
    });
    expect(result.id).toBe(1);
  });
});
