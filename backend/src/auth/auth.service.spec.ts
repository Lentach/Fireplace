import { Test, TestingModule } from '@nestjs/testing';
import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { UsersService } from '../users/users.service';
import { RefreshTokensService } from './refresh-tokens.service';
import { User } from '../users/user.entity';
import { DevicesService } from '../key-bundles/devices.service';

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
  let devicesService: jest.Mocked<Pick<DevicesService, 'resolveLoginDeviceId'>>;

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
        {
          // A login resolves the account's LIVE PRIMARY (amendment (xxviii)) —
          // device 1 for every single-device account, which is what the login
          // laws below assume.
          provide: DevicesService,
          useValue: {
            resolveLoginDeviceId: jest.fn(() => Promise.resolve(1)),
          },
        },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
    usersService = module.get(UsersService);
    jwtService = module.get(JwtService);
    refreshTokensService = module.get(RefreshTokensService);
    devicesService = module.get(DevicesService);
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
        deviceId: 1,
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
      // Session and token agree on the device from the first login (§4).
      expect(refreshTokensService.createToken).toHaveBeenCalledWith(1, 1);
      expect(jwtService.sign).toHaveBeenCalledWith({
        sub: 1,
        username: 'testuser',
        tag: '0427',
        deviceId: 1,
      });
      expect(result).toEqual({
        access_token: 'mock_jwt_token',
        refresh_token: 'mock_refresh_plain',
      });
    });

    it('logs in as the account LIVE PRIMARY, not a hardcoded device 1', async () => {
      // The lockout this prevents: a §6.2 reset revokes the pre-reset roster
      // and moves the account onto a freshly allocated id (amendment
      // (xxviii)). A login that kept claiming device 1 would mint a token for
      // a REVOKED device, which both §5.5 session gates then refuse — the
      // owner locked out with the correct password and no way back in.
      usersService.findByUsernameAndTag.mockResolvedValue(mockUser as User);
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);
      devicesService.resolveLoginDeviceId.mockResolvedValue(4);

      await service.login('testuser#0427', 'ValidPass1');

      expect(devicesService.resolveLoginDeviceId).toHaveBeenCalledWith(1);
      expect(refreshTokensService.createToken).toHaveBeenCalledWith(1, 4);
      expect(jwtService.sign).toHaveBeenCalledWith(
        expect.objectContaining({ deviceId: 4 }),
      );
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
      refreshTokensService.consumeAndSlide.mockResolvedValue({
        userId: 1,
        deviceId: 2,
      });
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
      // The reissued token keeps naming the SAME device: silently becoming
      // device 1 would hand this session another device's key namespace.
      expect(jwtService.sign).toHaveBeenCalledWith({
        sub: 1,
        username: 'testuser',
        tag: '0427',
        deviceId: 2,
      });
    });

    it('treats a session predating the device column as device 1', async () => {
      refreshTokensService.consumeAndSlide.mockResolvedValue({
        userId: 1,
        deviceId: null,
      });
      usersService.findById.mockResolvedValue(mockUser as User);

      await service.refreshWithToken('legacy_refresh');

      // Read the recorded call rather than referencing the mocked method
      // again: an unbound method reference is the lint debt this file already
      // carries, and new code should not add to it.
      const signed = jwtService.sign.mock.calls.at(-1)?.[0] as {
        deviceId?: number;
      };
      expect(signed.deviceId).toBe(1);
    });

    it('throws when user row missing after sliding refresh', async () => {
      refreshTokensService.consumeAndSlide.mockResolvedValue({
        userId: 99,
        deviceId: 1,
      });
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
