// backend/src/secret-notes/secret-notes.service.spec.ts
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { SecretNotesService } from './secret-notes.service';
import { SecretNote } from './secret-note.entity';

const mockRepo = () => ({
  create: jest.fn(),
  save: jest.fn(),
  findOne: jest.fn(),
  delete: jest.fn(),
  query: jest.fn(),
});

describe('SecretNotesService', () => {
  let service: SecretNotesService;
  let repo: ReturnType<typeof mockRepo>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        SecretNotesService,
        { provide: getRepositoryToken(SecretNote), useFactory: mockRepo },
      ],
    }).compile();

    service = module.get(SecretNotesService);
    repo = module.get(getRepositoryToken(SecretNote));
  });

  describe('create', () => {
    it('returns a token and saves the note', async () => {
      const note = { token: 'abc123', ciphertext: 'enc', expiresAt: new Date(), creatorId: 1 };
      repo.create.mockReturnValue(note);
      repo.save.mockResolvedValue(note);

      const result = await service.create('enc', 7200, 1);

      expect(repo.save).toHaveBeenCalled();
      expect(result.token).toHaveLength(32);
    });
  });

  describe('revealAndDelete', () => {
    it('returns ciphertext when note found and not expired', async () => {
      // TypeORM postgres driver returns [rows, rowCount] for DELETE ... RETURNING.
      repo.query.mockResolvedValue([[{ ciphertext: 'enc' }], 1]);
      const result = await service.revealAndDelete('tok');
      expect(result).toEqual({ ciphertext: 'enc' });
      expect(repo.query).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM secret_notes'),
        ['tok'],
      );
    });

    it('returns null when note not found or expired', async () => {
      repo.query.mockResolvedValue([[], 0]);
      const result = await service.revealAndDelete('missing');
      expect(result).toBeNull();
    });

    it('returns null when the driver yields a non-array rows slot', async () => {
      // The Array.isArray guard turns a non-array rows slot into null, not a crash.
      repo.query.mockResolvedValue([undefined, 0]);
      const result = await service.revealAndDelete('weird');
      expect(result).toBeNull();
    });

    it('queries the quoted camelCase column, never snake_case', async () => {
      // Regression: unquoted expires_at raised Postgres 42703 and 500'd reveal forever.
      repo.query.mockResolvedValue([[], 0]);
      await service.revealAndDelete('tok');
      const sql = repo.query.mock.calls[0][0] as string;
      expect(sql).toContain('"expiresAt"');
      expect(sql).not.toContain('expires_at');
    });
  });

  describe('findByToken', () => {
    it('returns null when note is expired', async () => {
      const past = new Date(Date.now() - 1000);
      repo.findOne.mockResolvedValue({ id: 1, token: 'tok', expiresAt: past });
      repo.delete.mockResolvedValue({});

      const result = await service.findByToken('tok');
      expect(result).toBeNull();
      expect(repo.delete).toHaveBeenCalledWith({ token: 'tok' });
    });

    it('returns note when valid', async () => {
      const future = new Date(Date.now() + 60000);
      const note = { id: 1, token: 'tok', ciphertext: 'enc', expiresAt: future };
      repo.findOne.mockResolvedValue(note);

      const result = await service.findByToken('tok');
      expect(result).toBe(note);
    });
  });

  describe('deleteExpiredNotes', () => {
    it('deletes expired unread notes in one repository call', async () => {
      repo.delete.mockResolvedValue({ affected: 3 });

      const deleted = await service.deleteExpiredNotes();

      expect(deleted).toBe(3);
      expect(repo.delete).toHaveBeenCalledWith({
        expiresAt: expect.objectContaining({
          _type: 'lessThan',
        }),
      });
    });
  });
});
