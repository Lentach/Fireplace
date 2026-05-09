import * as bcrypt from 'bcrypt';
import { UsersService } from './users.service';

jest.mock('bcrypt', () => ({
  compare: jest.fn(),
  hash: jest.fn(),
}));

describe('UsersService.deleteAccount – cascade', () => {
  let service: UsersService;

  const mockUser = {
    id: 7,
    password: '$2b$10$validhashhere........................................',
    username: 'u',
    tag: '1234',
  };

  const mockRepo = {
    findOne: jest.fn(),
    manager: {
      find: jest.fn().mockResolvedValue([]),
    },
  };
  const mockStorage = { deleteAvatar: jest.fn() };
  const mockFcm = { removeByUserId: jest.fn().mockResolvedValue(undefined) };
  const mockWebPush = { removeByUserId: jest.fn().mockResolvedValue(undefined) };
  const mockKeyBundles = { deleteByUserId: jest.fn().mockResolvedValue(undefined) };

  const mockMessagesService = {
    findMediaUrlsByConversation: jest.fn().mockResolvedValue([]),
  };
  const mockMediaCleanup = { deleteMediaFile: jest.fn().mockResolvedValue(undefined) };
  const mockRefreshTokens = { revokeAllForUser: jest.fn().mockResolvedValue(undefined) };

  const mockManager = {
    find: jest.fn().mockResolvedValue([]),
    delete: jest.fn().mockResolvedValue(undefined),
    remove: jest.fn().mockResolvedValue(undefined),
  };

  const mockDataSource = {
    transaction: jest.fn().mockImplementation(async (fn: (m: typeof mockManager) => Promise<void>) => {
      await fn(mockManager);
    }),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockRepo.manager.find.mockResolvedValue([]);
    mockManager.find.mockResolvedValue([]);
    mockManager.delete.mockResolvedValue(undefined);
    mockManager.remove.mockResolvedValue(undefined);

    service = new UsersService(
      mockRepo as any,
      mockStorage as any,
      mockFcm as any,
      mockWebPush as any,
      mockKeyBundles as any,
      mockDataSource as any,
      mockMessagesService as any,
      mockMediaCleanup as any,
      mockRefreshTokens as any,
    );
  });

  it('calls deleteByUserId on key bundles service before user removal', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await service.deleteAccount(7, 'correct-password');

    expect(mockKeyBundles.deleteByUserId).toHaveBeenCalledWith(7);
  });

  it('calls fcm removeByUserId', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await service.deleteAccount(7, 'correct-password');

    expect(mockFcm.removeByUserId).toHaveBeenCalledWith(7);
  });

  it('calls web push removeByUserId', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await service.deleteAccount(7, 'correct-password');

    expect(mockWebPush.removeByUserId).toHaveBeenCalledWith(7);
  });

  it('rejects with UnauthorizedException when password is wrong', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(false);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await expect(service.deleteAccount(7, 'wrong')).rejects.toThrow();
  });
});
