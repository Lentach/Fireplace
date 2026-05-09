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
      'createToken' | 'consumeAndRotate'
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
            consumeAndRotate: jest.fn(),
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
      expect(usersService.create).toHaveBeenCalledWith('testuser', 'ValidPass1');
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

    it('should throw when user not found', async () => {
      usersService.findByUsername.mockResolvedValue([]);
      await expect(service.login('unknown', 'ValidPass1')).rejects.toThrow(
        UnauthorizedException,
      );
      await expect(service.login('unknown', 'ValidPass1')).rejects.toThrow(
        'Invalid credentials',
      );
      expect(bcrypt.compare).not.toHaveBeenCalled();
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
  });

  describe('refreshWithToken', () => {
    it('returns new access_token and rotated refresh_token when refresh valid', async () => {
      refreshTokensService.consumeAndRotate.mockResolvedValue({
        userId: 1,
        newPlain: 'rotated_refresh_plain',
      });
      usersService.findById.mockResolvedValue(mockUser as User);

      const result = await service.refreshWithToken('incoming_refresh');

      expect(refreshTokensService.consumeAndRotate).toHaveBeenCalledWith(
        'incoming_refresh',
      );
      expect(usersService.findById).toHaveBeenCalledWith(1);
      expect(result).toEqual({
        access_token: 'mock_jwt_token',
        refresh_token: 'rotated_refresh_plain',
      });
      expect(jwtService.sign).toHaveBeenCalledWith({
        sub: 1,
        username: 'testuser',
        tag: '0427',
      });
    });

    it('throws when user row missing after rotate', async () => {
      refreshTokensService.consumeAndRotate.mockResolvedValue({
        userId: 99,
        newPlain: 'rotated',
      });
      usersService.findById.mockResolvedValue(null);

      await expect(service.refreshWithToken('r')).rejects.toThrow(
        UnauthorizedException,
      );
    });
  });
});
