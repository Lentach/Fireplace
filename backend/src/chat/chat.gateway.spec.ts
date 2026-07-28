import { JwtService } from '@nestjs/jwt';
import { ChatGateway } from './chat.gateway';
import { UsersService } from '../users/users.service';
import { Socket } from 'socket.io';

function createGateway(): ChatGateway {
  const noop = {} as any;
  const keyExchange = {
    deliverPendingSessionRebuilds: jest.fn(),
  } as any;
  return new ChatGateway(
    { verify: jest.fn() } as unknown as JwtService,
    { findById: jest.fn() } as unknown as UsersService,
    noop,
    noop,
    noop,
    keyExchange,
    noop,
    noop,
    noop,
    noop,
  );
}

function createMockClient(
  overrides: Partial<{
    token: string | undefined;
    emit: jest.Mock;
    disconnect: jest.Mock;
    join: jest.Mock;
    id: string;
  }> = {},
) {
  const emit = overrides.emit ?? jest.fn();
  const disconnect = overrides.disconnect ?? jest.fn();
  const join = overrides.join ?? jest.fn();
  return {
    id: overrides.id ?? 'socket-test-1',
    handshake: {
      auth: overrides.token !== undefined ? { token: overrides.token } : {},
    },
    data: {} as Record<string, unknown>,
    emit,
    disconnect,
    join,
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
    expect(client.join).toHaveBeenCalledWith('user:42');
    expect(
      (gateway as any).chatKeyExchangeService.deliverPendingSessionRebuilds,
    ).toHaveBeenCalledWith(client);
    expect(client.emit).toHaveBeenCalledWith('socketReady', {
      serverTime: expect.any(String),
    });
    // The client parses this and refuses to destroy expired plaintext when it
    // cannot. An unparseable stamp would silently disable that path forever.
    const readyCall = (client.emit as jest.Mock).mock.calls.find(
      (call) => call[0] === 'socketReady',
    );
    expect(Number.isNaN(Date.parse(readyCall[1].serverTime))).toBe(false);
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

    expect(client.emit).not.toHaveBeenCalledWith(
      'socketReady',
      expect.anything(),
    );
    expect(client.disconnect).toHaveBeenCalled();
    expect(jwtService.verify).not.toHaveBeenCalled();
  });

  it('does not emit socketReady when user is not found', async () => {
    const client = createMockClient({ token: 'valid-jwt' });
    jwtService.verify.mockReturnValue({ sub: 99 });
    usersService.findById.mockResolvedValue(null);

    await gateway.handleConnection(client as any);

    expect(client.emit).not.toHaveBeenCalledWith(
      'socketReady',
      expect.anything(),
    );
    expect(client.disconnect).toHaveBeenCalled();
  });

  it('does not emit socketReady when JWT verification fails', async () => {
    const client = createMockClient({ token: 'bad-jwt' });
    jwtService.verify.mockImplementation(() => {
      throw new Error('invalid token');
    });

    await gateway.handleConnection(client as any);

    expect(client.emit).not.toHaveBeenCalledWith(
      'socketReady',
      expect.anything(),
    );
    expect(client.disconnect).toHaveBeenCalled();
    expect(usersService.findById).not.toHaveBeenCalled();
  });

  it('disconnects when the token predates a password change', async () => {
    const client = createMockClient({ token: 'old-jwt' });
    jwtService.verify.mockReturnValue({ sub: 7, iat: 1000 });
    usersService.findById.mockResolvedValue({
      id: 7,
      username: 'me',
      tag: '0007',
      passwordChangedAt: new Date(2000 * 1000), // changedAt=2000s > iat=1000s -> invalid
    });

    await gateway.handleConnection(client as unknown as Socket);

    expect(client.disconnect).toHaveBeenCalled();
    expect(client.emit).not.toHaveBeenCalledWith(
      'socketReady',
      expect.anything(),
    );
  });
});

describe('ChatGateway handleDisconnect (stale-socket guard)', () => {
  let gateway: ChatGateway;
  let jwtService: { verify: jest.Mock };
  let usersService: { findById: jest.Mock };

  beforeEach(() => {
    gateway = createGateway();
    jwtService = (gateway as any).jwtService;
    usersService = (gateway as any).usersService;
    jwtService.verify.mockReturnValue({ sub: 37 });
    usersService.findById.mockResolvedValue({
      id: 37,
      username: 'me',
      tag: '0037',
    });
  });

  // iOS PWA suspend/resume: the device reconnects with a NEW socket while the
  // abandoned OLD socket lingers on the server until its ping times out (~20s).
  // When that stale disconnect finally fires, it must NOT evict the live socket —
  // otherwise onlineUsers.get(userId) goes undefined and peers' newMessage emits
  // silently fall back to push (notification arrives, message never delivered live).
  it('a stale old-socket disconnect does NOT unregister the live new socket', async () => {
    const oldSocket = createMockClient({ token: 'jwt', id: 'OLD' });
    const newSocket = createMockClient({ token: 'jwt', id: 'NEW' });

    await gateway.handleConnection(oldSocket as any); // onlineUsers[37] = OLD
    await gateway.handleConnection(newSocket as any); // reconnect → onlineUsers[37] = NEW

    gateway.handleDisconnect(oldSocket as any); // abandoned old socket times out

    const onlineUsers: Map<number, string> = (gateway as any).onlineUsers;
    expect(onlineUsers.get(37)).toBe('NEW');
  });

  it('disconnect of the current socket DOES unregister the user', async () => {
    const socket = createMockClient({ token: 'jwt', id: 'ONLY' });

    await gateway.handleConnection(socket as any);
    gateway.handleDisconnect(socket as any);

    const onlineUsers: Map<number, string> = (gateway as any).onlineUsers;
    expect(onlineUsers.has(37)).toBe(false);
  });
});

describe('ChatGateway handleGetServerTime', () => {
  it('answers with a parseable ISO serverTime on the serverTime event', () => {
    const gateway = createGateway();
    const client = createMockClient();

    gateway.handleGetServerTime(client as any);

    expect(client.emit).toHaveBeenCalledWith('serverTime', {
      serverTime: expect.any(String),
    });
    // Same contract as socketReady: the client refuses to destroy expired
    // plaintext without a clock it can parse, so an unparseable stamp would
    // silently disable the in-session sweep this event exists to feed.
    const call = (client.emit as jest.Mock).mock.calls.find(
      (c) => c[0] === 'serverTime',
    );
    expect(Number.isNaN(Date.parse(call[1].serverTime))).toBe(false);
  });
});
