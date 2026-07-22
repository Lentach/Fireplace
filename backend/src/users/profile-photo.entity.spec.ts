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

    const storageKeyColumn = dataSource
      .getMetadata(ProfilePhoto)
      .findColumnWithPropertyName('storageKey');

    // Guards against a regression to a length-limited varchar column.
    expect(storageKeyColumn?.type).toBe('text');
    // Legacy rows predate storageKey, so the column must stay nullable.
    expect(storageKeyColumn?.isNullable).toBe(true);
  });
});
