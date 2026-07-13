import { DataSource } from 'typeorm';
import { ProfilePhoto } from './profile-photo.entity';
import { User } from './user.entity';
import { UsersService } from './users.service';

describe('UsersService.addProfilePhoto', () => {
  const profilePhotoRepo = {
    find: jest.fn(),
  };
  const transactionalPhotoRepo = {
    find: jest.fn(),
    create: jest.fn(),
    save: jest.fn(),
  };
  const manager = {
    findOne: jest.fn(),
    getRepository: jest.fn(),
    update: jest.fn(),
  };
  const dataSource = {
    transaction: jest.fn(),
  };
  const service = new UsersService(
    {} as any,
    profilePhotoRepo as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    dataSource as unknown as DataSource,
    {} as any,
    {} as any,
    {} as any,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    profilePhotoRepo.find.mockResolvedValue([]);
    manager.findOne.mockResolvedValue({ id: 7 });
    manager.getRepository.mockReturnValue(transactionalPhotoRepo);
    manager.update.mockResolvedValue(undefined);
    dataSource.transaction.mockImplementation(async (callback) => callback(manager));
    transactionalPhotoRepo.create.mockImplementation((photo) => photo);
    transactionalPhotoRepo.save.mockImplementation(async (photo) => ({ id: 1, ...photo }));
  });

  it('writes a primary photo and the legacy primary pointer atomically', async () => {
    const saved = {
      id: 1,
      userId: 7,
      url: '/avatars/new.jpg',
      storageKey: 'avatars/new.jpg',
      isPrimary: true,
    };
    transactionalPhotoRepo.find
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([saved]);

    await expect(
      service.addProfilePhoto(7, saved.url, saved.storageKey),
    ).resolves.toEqual([saved]);

    expect(dataSource.transaction).toHaveBeenCalledTimes(1);
    expect(manager.findOne).toHaveBeenCalledWith(User, {
      where: { id: 7 },
      lock: { mode: 'pessimistic_write' },
    });
    expect(manager.getRepository).toHaveBeenCalledWith(ProfilePhoto);
    expect(manager.update).toHaveBeenCalledWith(User, 7, {
      profilePictureUrl: saved.url,
      profilePicturePublicId: saved.storageKey,
    });
  });

  it('rejects a full gallery while holding the owner lock', async () => {
    transactionalPhotoRepo.find.mockResolvedValue([
      { id: 1 },
      { id: 2 },
      { id: 3 },
    ]);

    await expect(
      service.addProfilePhoto(7, '/avatars/four.jpg', 'avatars/four.jpg'),
    ).rejects.toThrow('A profile can have at most three photos');

    expect(manager.findOne).toHaveBeenCalledWith(User, {
      where: { id: 7 },
      lock: { mode: 'pessimistic_write' },
    });
    expect(transactionalPhotoRepo.save).not.toHaveBeenCalled();
  });
});
