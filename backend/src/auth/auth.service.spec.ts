import { Test, TestingModule } from '@nestjs/testing';
import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { UsersService } from '../users/users.service';
import { RefreshTokensService } from './refresh-tokens.service';
import { User } from '../users/user.entity';

jest.mock('bcrypt', () => ({
  compare: jest.fn(),
  hash: jest.fn((val: string) => Promise.resolve(`hashed_${val}`)),
}));

describe('AuthService', () => {
  let service: AuthService;
  let usersService: jest.Mocked<UsersService>;
  let jwtService: jest.Mocked<JwtService>;
  let refreshTokensService: jest.Mocked<
    Pick<
      RefreshTokensService,
      'createToken' | 'consumeAndSlide' | 'revokeByPlain'
    >
  >;

  const mockUser: Partial<User> = {
    id: 1,
    username: 'testuser',
    tag: '0427',
    password: 'hashed_password',
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: UsersService,
          useValue: {
            create: jest.fn(),
            findByUsername: jest.fn(),
            findByUsernameAndTag: jest.fn(),
            findById: jest.fn(),
          },
        },
        {
          provide: JwtService,
          useValue: {
            sign: jest.fn(() => 'mock_jwt_token'),
          },
        },
        {
          provide: RefreshTokensService,
          useValue: {
            createToken: jest.fn(() => Promise.resolve('mock_refresh_plain')),
            consumeAndSlide: jest.fn(),
            revokeByPlain: jest.fn(() => Promise.resolve()),
          },
        },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
    usersService = module.get(UsersService);
    jwtService = module.get(JwtService);
    refreshTokensService = module.get(RefreshTokensService);
    jest.clearAllMocks();
  });

  describe('register', () => {
    it('should create user and return id/username/tag', async () => {
      usersService.create.mockResolvedValue(mockUser as User);
      const result = await service.register('testuser', 'ValidPass1');
      expect(usersService.create).toHaveBeenCalledWith(
        'testuser',
        'ValidPass1',
      );
      expect(result).toEqual({ id: 1, username: 'testuser', tag: '0427' });
    });

    // Password strength validation is enforced at the DTO layer (RegisterDto).
    // See password.spec.ts for those tests.
  });

  describe('login', () => {
    it('should return access_token for valid credentials', async () => {
      usersService.findByUsername.mockResolvedValue([mockUser as User]);
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
      const result = await service.login('testuser', 'ValidPass1');
      expect(result).toEqual({
        access_token: 'mock_jwt_token',
        refresh_token: 'mock_refresh_plain',
      });
      expect(jwtService.sign).toHaveBeenCalledWith({
        sub: 1,
        username: 'testuser',
        tag: '0427',
      });
    });

    it('trims username#tag identifiers, signs a JWT, and creates a refresh token for valid credentials', async () => {
      usersService.findByUsernameAndTag.mockResolvedValue(mockUser as User);
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);

      const result = await service.login('  testuser # 0427  ', 'ValidPass1');

      expect(usersService.findByUsernameAndTag).toHaveBeenCalledWith(
        'testuser',
        '0427',
      );
      expect(usersService.findByUsername).not.toHaveBeenCalled();
      expect(bcrypt.compare).toHaveBeenCalledWith(
        'ValidPass1',
        'hashed_password',
      );
      expect(refreshTokensService.createToken).toHaveBeenCalledWith(1);
      expect(jwtService.sign).toHaveBeenCalledWith({
        sub: 1,
        username: 'testuser',
        tag: '0427',
      });
      expect(result).toEqual({
        access_token: 'mock_jwt_token',
        refresh_token: 'mock_refresh_plain',
      });
    });

    it('returns the generic failure and still runs a bcrypt compare for ambiguous bare usernames (no enumeration)', async () => {
      usersService.findByUsername.mockResolvedValue([
        mockUser as User,
        { ...mockUser, id: 2, tag: '9001' } as User,
      ]);
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);

      // Must be indistinguishable from any other bad login: same message, and a
      // real bcrypt compare so the branch is not measurably faster (timing enum).
      await expect(service.login('testuser', 'ValidPass1')).rejects.toThrow(
        new UnauthorizedException('Invalid credentials'),
      );

      expect(usersService.findByUsername).toHaveBeenCalledWith('testuser');
      expect(usersService.findByUsernameAndTag).not.toHaveBeenCalled();
      expect(bcrypt.compare).toHaveBeenCalledTimes(1);
      expect(refreshTokensService.createToken).not.toHaveBeenCalled();
      expect(jwtService.sign).not.toHaveBeenCalled();
    });

    it('should throw when user not found', async () => {
      usersService.findByUsername.mockResolvedValue([]);
      await expect(service.login('unknown', 'ValidPass1')).rejects.toThrow(
        UnauthorizedException,
      );
      await expect(service.login('unknown', 'ValidPass1')).rejects.toThrow(
        'Invalid credentials',
      );
      // Not-found path now performs a constant-time dummy bcrypt.compare to
      // defeat timing-based user enumeration.
      expect(bcrypt.compare).toHaveBeenCalled();
    });

    it('should throw when password invalid', async () => {
      usersService.findByUsername.mockResolvedValue([mockUser as User]);
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);
      await expect(service.login('testuser', 'WrongPass1')).rejects.toThrow(
        UnauthorizedException,
      );
      await expect(service.login('testuser', 'WrongPass1')).rejects.toThrow(
        'Invalid credentials',
      );
    });

    it('treats an identifier with a "#" but empty tag as no-match via the timing-safe path', async () => {
      // 'user#' splits to ['user', ''] -> the `if (u && t)` guard is false, so
      // user stays null and we must fall through to the dummy bcrypt.compare
      // without ever querying with an empty tag.
      await expect(service.login('user#', 'ValidPass1')).rejects.toThrow(
        new UnauthorizedException('Invalid credentials'),
      );

      expect(usersService.findByUsernameAndTag).not.toHaveBeenCalled();
      expect(usersService.findByUsername).not.toHaveBeenCalled();
      // Constant-time guard still runs a real compare to defeat enumeration.
      expect(bcrypt.compare).toHaveBeenCalledTimes(1);
    });
  });

  describe('refreshWithToken', () => {
    it('returns new access_token and slid refresh_token when refresh valid', async () => {
      refreshTokensService.consumeAndSlide.mockResolvedValue(1);
      usersService.findById.mockResolvedValue(mockUser as User);

      const result = await service.refreshWithToken('incoming_refresh');

      expect(refreshTokensService.consumeAndSlide).toHaveBeenCalledWith(
        'incoming_refresh',
      );
      expect(usersService.findById).toHaveBeenCalledWith(1);
      expect(result).toEqual({
        access_token: 'mock_jwt_token',
        refresh_token: 'incoming_refresh',
      });
      expect(jwtService.sign).toHaveBeenCalledWith({
        sub: 1,
        username: 'testuser',
        tag: '0427',
      });
    });

    it('throws when user row missing after sliding refresh', async () => {
      refreshTokensService.consumeAndSlide.mockResolvedValue(99);
      usersService.findById.mockResolvedValue(null);

      await expect(service.refreshWithToken('r')).rejects.toThrow(
        UnauthorizedException,
      );
    });
  });

  describe('logoutRefreshToken', () => {
    it('forwards the plain token to refreshTokensService.revokeByPlain', async () => {
      await service.logoutRefreshToken('plain-to-revoke');

      expect(refreshTokensService.revokeByPlain).toHaveBeenCalledTimes(1);
      expect(refreshTokensService.revokeByPlain).toHaveBeenCalledWith(
        'plain-to-revoke',
      );
    });
  });
});
