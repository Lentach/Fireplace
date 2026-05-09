import { Test } from '@nestjs/testing';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

const createAuthServiceMock = () => ({
  register: jest.fn(),
  login: jest.fn(),
  refreshWithToken: jest.fn(),
  logoutRefreshToken: jest.fn(),
});

describe('AuthController', () => {
  let controller: AuthController;
  let authService: ReturnType<typeof createAuthServiceMock>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [AuthController],
      providers: [{ provide: AuthService, useFactory: createAuthServiceMock }],
    }).compile();

    controller = module.get(AuthController);
    authService = module.get(AuthService);
  });

  it('register forwards username and password to AuthService', async () => {
    authService.register.mockResolvedValue({ token: 'register-token' });

    const result = await controller.register({
      username: 'alice',
      password: 'StrongPass123!',
    });

    expect(authService.register).toHaveBeenCalledWith(
      'alice',
      'StrongPass123!',
    );
    expect(result).toEqual({ token: 'register-token' });
  });

  it('login forwards identifier and password to AuthService', async () => {
    authService.login.mockResolvedValue({
      access_token: 'a',
      refresh_token: 'r',
    });

    const result = await controller.login({
      identifier: 'alice#1234',
      password: 'StrongPass123!',
    });

    expect(authService.login).toHaveBeenCalledWith(
      'alice#1234',
      'StrongPass123!',
    );
    expect(result).toEqual({
      access_token: 'a',
      refresh_token: 'r',
    });
  });
});
