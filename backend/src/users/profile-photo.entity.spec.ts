import { DataSource } from 'typeorm';
import { ProfilePhoto } from './profile-photo.entity';
import { User } from './user.entity';

describe('ProfilePhoto entity', () => {
  it('initializes nullable storageKey as a PostgreSQL text column', async () => {
    const dataSource = new DataSource({
      type: 'postgres',
      database: 'fireplace_test',
      entities: [User, ProfilePhoto],
    });

    await expect((dataSource as any).buildMetadatas()).resolves.toBeUndefined();

    expect(
      dataSource
        .getMetadata(ProfilePhoto)
        .findColumnWithPropertyName('storageKey')?.type,
    ).toBe('text');
  });
});
