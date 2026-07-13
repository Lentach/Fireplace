import { User } from '../../users/user.entity';

export class UserMapper {
  static toPayload(user: User) {
    const profilePhotos = user.profilePhotos ?? [];
    const primaryPhoto = profilePhotos.find((photo) => photo.isPrimary);
    return {
      id: user.id,
      username: user.username,
      tag: user.tag,
      about: user.about ?? null,
      profilePictureUrl: primaryPhoto?.url ?? user.profilePictureUrl,
      profilePhotos: [...profilePhotos]
        .sort((left, right) => {
          if (left.isPrimary !== right.isPrimary) return left.isPrimary ? -1 : 1;
          return left.createdAt.getTime() - right.createdAt.getTime();
        })
        .map((photo) => ({
          id: photo.id,
          url: photo.url,
          isPrimary: photo.isPrimary,
          createdAt: photo.createdAt,
        })),
    };
  }

}
