import { BadRequestException } from '@nestjs/common';
import { UsersController } from './users.controller';

describe('UsersController', () => {
  const usersService = {
    getProfilePhotos: jest.fn(),
    addProfilePhoto: jest.fn(),
  };
  const storageService = {
    uploadAvatar: jest.fn(),
    deleteAvatar: jest.fn(),
  };
  const controller = new UsersController(
    usersService as any,
    storageService as any,
    {} as any,
    {} as any,
  );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('deletes a newly uploaded asset when profile-photo persistence fails', async () => {
    usersService.getProfilePhotos.mockResolvedValue([]);
    storageService.uploadAvatar.mockResolvedValue({
      secureUrl: '/avatars/new-photo.jpg',
      publicId: 'avatars/new-photo.jpg',
    });
    usersService.addProfilePhoto.mockRejectedValue(
      new BadRequestException('A profile can have at most three photos'),
    );
    storageService.deleteAvatar.mockResolvedValue(undefined);

    await expect(
      controller.uploadProfilePicture(
        {
          buffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
          mimetype: 'image/png',
        } as Express.Multer.File,
        { user: { id: 7 } },
      ),
    ).rejects.toThrow('A profile can have at most three photos');

    expect(storageService.deleteAvatar).toHaveBeenCalledWith(
      'avatars/new-photo.jpg',
    );
  });
});
