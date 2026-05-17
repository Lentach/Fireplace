import { JwtService } from '@nestjs/jwt';
import { ChatGateway } from './chat.gateway';
import { UsersService } from '../users/users.service';

function createGateway(): ChatGateway {
  const noop = {} as any;
  return new ChatGateway(
    { verify: jest.fn() } as unknown as JwtService,
    { findById: jest.fn() } as unknown as UsersService,
    noop,
    noop,
    noop,
    noop,
    noop,
    noop,
    noop,
    noop,
  );
}

function createMockClient(overrides: Partial<{
  token: string | undefined;
  emit: jest.Mock;
  disconnect: jest.Mock;
}> = {}) {
  const emit = overrides.emit ?? jest.fn();
  const disconnect = overrides.disconnect ?? jest.fn();
  return {
    id: 'socket-test-1',
    handshake: {
      auth: overrides.token !== undefined ? { token: overrides.token } : {},
    },
    data: {} as Record<string, unknown>,
    emit,
    disconnect,
  };
}

describe('ChatGateway handleConnection', () => {
  let gateway: ChatGateway;
  let jwtService: { verify: jest.Mock };
  let usersService: { findById: jest.Mock };

  beforeEach(() => {
    gateway = createGateway();
    jwtService = (gateway as any).jwtService;
    usersService = (gateway as any).usersService;
  });

  it('emits socketReady after successful JWT auth and user lookup', async () => {
    const client = createMockClient({ token: 'valid-jwt' });
    jwtService.verify.mockReturnValue({ sub: 42 });
    usersService.findById.mockResolvedValue({
      id: 42,
      username: 'alice',
      tag: '0001',
    });

    await gateway.handleConnection(client as any);

    expect(jwtService.verify).toHaveBeenCalledWith('valid-jwt');
    expect(usersService.findById).toHaveBeenCalledWith(42);
    expect(client.emit).toHaveBeenCalledWith('socketReady', {});
    expect(client.disconnect).not.toHaveBeenCalled();
    expect(client.data.user).toEqual({
      id: 42,
      username: 'alice',
      tag: '0001',
    });
  });

  it('does not emit socketReady when token is missing', async () => {
    const client = createMockClient();

    await gateway.handleConnection(client as any);

    expect(client.emit).not.toHaveBeenCalledWith('socketReady', {});
    expect(client.disconnect).toHaveBeenCalled();
    expect(jwtService.verify).not.toHaveBeenCalled();
  });

  it('does not emit socketReady when user is not found', async () => {
    const client = createMockClient({ token: 'valid-jwt' });
    jwtService.verify.mockReturnValue({ sub: 99 });
    usersService.findById.mockResolvedValue(null);

    await gateway.handleConnection(client as any);

    expect(client.emit).not.toHaveBeenCalledWith('socketReady', {});
    expect(client.disconnect).toHaveBeenCalled();
  });

  it('does not emit socketReady when JWT verification fails', async () => {
    const client = createMockClient({ token: 'bad-jwt' });
    jwtService.verify.mockImplementation(() => {
      throw new Error('invalid token');
    });

    await gateway.handleConnection(client as any);

    expect(client.emit).not.toHaveBeenCalledWith('socketReady', {});
    expect(client.disconnect).toHaveBeenCalled();
    expect(usersService.findById).not.toHaveBeenCalled();
  });
});
