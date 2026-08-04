import * as bcrypt from 'bcrypt';
import { UsersService } from './users.service';
import { UnauthorizedException } from '@nestjs/common';
import { User } from './user.entity';
import { Message } from '../messages/message.entity';
import { Conversation } from '../conversations/conversation.entity';
import { FriendRequest } from '../friends/friend-request.entity';

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
  const mockProfilePhotoRepo = {
    find: jest.fn().mockResolvedValue([]),
  };
  const mockStorage = { deleteAvatar: jest.fn() };
  const mockFcm = { removeByUserId: jest.fn().mockResolvedValue(undefined) };
  const mockWebPush = {
    removeByUserId: jest.fn().mockResolvedValue(undefined),
  };
  const mockKeyBundles = {
    deleteByUserId: jest.fn().mockResolvedValue(undefined),
  };

  const mockMessagesService = {
    findMediaUrlsByConversation: jest.fn().mockResolvedValue([]),
  };
  const mockMediaCleanup = {
    deleteMediaFile: jest.fn().mockResolvedValue(undefined),
  };
  const mockRefreshTokens = {
    revokeAllForUser: jest.fn().mockResolvedValue(undefined),
  };

  const mockManager = {
    find: jest.fn().mockResolvedValue([]),
    delete: jest.fn().mockResolvedValue(undefined),
    remove: jest.fn().mockResolvedValue(undefined),
  };

  const mockDataSource = {
    transaction: jest
      .fn()
      .mockImplementation(
        async (fn: (m: typeof mockManager) => Promise<void>) => {
          await fn(mockManager);
        },
      ),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockRepo.manager.find.mockResolvedValue([]);
    mockManager.find.mockResolvedValue([]);
    mockProfilePhotoRepo.find.mockResolvedValue([]);
    mockManager.delete.mockResolvedValue(undefined);
    mockManager.remove.mockResolvedValue(undefined);

    service = new UsersService(
      mockRepo as any,
      mockProfilePhotoRepo as unknown as never,
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

  it('purges key bundles AFTER the user-removal transaction (post-commit backstop to the FK cascade)', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await service.deleteAccount(7, 'correct-password');

    expect(mockKeyBundles.deleteByUserId).toHaveBeenCalledWith(7);
    expect(mockManager.remove).toHaveBeenCalledWith(User, mockUser);
    // Irreversible external cleanup must run only once the account is durably
    // gone: the user row (and its ON DELETE CASCADE side rows) commits first,
    // then the idempotent explicit purge runs as a backstop. A regression that
    // destroys key bundles BEFORE the transaction re-opens the zombie window.
    expect(
      mockKeyBundles.deleteByUserId.mock.invocationCallOrder[0],
    ).toBeGreaterThan(mockManager.remove.mock.invocationCallOrder[0]);
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

    await expect(service.deleteAccount(7, 'wrong')).rejects.toThrow(
      UnauthorizedException,
    );

    // A wrong password must abort before any destructive work fires.
    expect(mockManager.remove).not.toHaveBeenCalled();
    expect(mockKeyBundles.deleteByUserId).not.toHaveBeenCalled();
    expect(mockStorage.deleteAvatar).not.toHaveBeenCalled();
  });

  it('deletes messages, conversations, friend requests, and the user inside the transaction', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue(mockUser);
    // First transactional manager.find is the Conversation lookup, second is
    // the FriendRequest lookup.
    const friendRequest = { id: 99 };
    mockManager.find
      .mockResolvedValueOnce([{ id: 11 }])
      .mockResolvedValueOnce([friendRequest]);

    await service.deleteAccount(7, 'correct-password');

    expect(mockManager.delete).toHaveBeenCalledWith(Message, {
      conversation: { id: 11 },
    });
    expect(mockManager.delete).toHaveBeenCalledWith(Conversation, { id: 11 });
    expect(mockManager.find).toHaveBeenCalledWith(
      FriendRequest,
      expect.anything(),
    );
    expect(mockManager.remove).toHaveBeenCalledWith([friendRequest]);
    expect(mockManager.remove).toHaveBeenCalledWith(User, mockUser);
    const userRemovals = mockManager.remove.mock.calls.filter(
      (args) => args[0] === User,
    );
    expect(userRemovals).toHaveLength(1);
  });

  it('deletes every unique avatar/media storage key exactly once', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue({
      ...mockUser,
      profilePicturePublicId: 'avatars/a.jpg',
    });
    mockProfilePhotoRepo.find.mockResolvedValue([
      { storageKey: 'avatars/a.jpg' },
      { storageKey: 'avatars/b.jpg' },
    ]);

    await service.deleteAccount(7, 'correct-password');

    expect(mockStorage.deleteAvatar).toHaveBeenCalledWith('avatars/a.jpg');
    expect(mockStorage.deleteAvatar).toHaveBeenCalledWith('avatars/b.jpg');
    // De-dup: a.jpg is both the avatar id and a photo key, purged only once.
    expect(mockStorage.deleteAvatar).toHaveBeenCalledTimes(2);
  });

  it('revokes refresh tokens before a failing transaction and performs no external destruction (no loginable zombie)', async () => {
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);
    mockRepo.findOne.mockResolvedValue({
      ...mockUser,
      profilePicturePublicId: 'avatars/a.jpg',
    });
    mockRepo.manager.find.mockResolvedValue([{ id: 11 }]);
    mockMessagesService.findMediaUrlsByConversation.mockResolvedValue([
      'https://media.example/media/msgs/x.bin',
    ]);
    // The DB transaction aborts mid-delete (in prod a concurrent send trips the
    // NO ACTION conversations FKs and rolls the whole thing back).
    mockDataSource.transaction.mockRejectedValueOnce(new Error('tx aborted'));

    await expect(service.deleteAccount(7, 'correct-password')).rejects.toThrow(
      'tx aborted',
    );

    // Session is killed up front, so a stolen refresh token cannot be exchanged
    // for a fresh access JWT: the "deleted" account is not loginable.
    expect(mockRefreshTokens.revokeAllForUser).toHaveBeenCalledWith(7);
    expect(
      mockRefreshTokens.revokeAllForUser.mock.invocationCallOrder[0],
    ).toBeLessThan(mockDataSource.transaction.mock.invocationCallOrder[0]);
    // Nothing irreversible happened: no keys, media, tokens or subscriptions
    // were destroyed, so the account is fully intact rather than a half-deleted
    // zombie that is unmessageable yet still loginable.
    expect(mockStorage.deleteAvatar).not.toHaveBeenCalled();
    expect(mockMediaCleanup.deleteMediaFile).not.toHaveBeenCalled();
    expect(mockKeyBundles.deleteByUserId).not.toHaveBeenCalled();
    expect(mockFcm.removeByUserId).not.toHaveBeenCalled();
    expect(mockWebPush.removeByUserId).not.toHaveBeenCalled();
  });
});
