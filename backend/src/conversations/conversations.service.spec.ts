import { ConversationsService } from './conversations.service';
import { Repository } from 'typeorm';
import { Conversation } from './conversation.entity';
import { Message } from '../messages/message.entity';
import { User } from '../users/user.entity';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';

const asUser = (id: number): User => ({ id }) as User;

describe('ConversationsService.findOrCreate', () => {
  let service: ConversationsService;
  let convRepo: jest.Mocked<Repository<Conversation>>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        ConversationsService,
        {
          provide: getRepositoryToken(Conversation),
          useValue: {
            findOne: jest.fn(),
            create: jest.fn((v) => v as Conversation),
            save: jest.fn(),
          },
        },
        {
          provide: getRepositoryToken(Message),
          useValue: { delete: jest.fn() },
        },
      ],
    }).compile();
    service = module.get(ConversationsService);
    convRepo = module.get(getRepositoryToken(Conversation));
  });

  it('returns the existing conversation without inserting when a pair already exists', async () => {
    const existing = { id: 7 } as Conversation;
    convRepo.findOne.mockResolvedValueOnce(existing);

    const result = await service.findOrCreate(asUser(1), asUser(2));

    expect(result).toBe(existing);
    expect(convRepo.save).not.toHaveBeenCalled();
  });

  it('inserts and returns a new conversation when no pair exists', async () => {
    const created = { id: 9 } as Conversation;
    convRepo.findOne.mockResolvedValueOnce(null);
    convRepo.save.mockResolvedValueOnce(created);

    const result = await service.findOrCreate(asUser(1), asUser(2));

    expect(result).toBe(created);
    expect(convRepo.save).toHaveBeenCalledTimes(1);
  });

  it('resolves a concurrent insert (Postgres 23505) to the single winning row instead of throwing', async () => {
    // Interleaving: existence check finds nothing, but a sibling request wins the
    // race and inserts first. The unique index (UQ_conversations_user_pair) makes
    // our save() reject with 23505; findOrCreate must re-read and return the one
    // surviving row — never a second conversation for the same pair.
    const winner = { id: 42 } as Conversation;
    convRepo.findOne
      .mockResolvedValueOnce(null) // initial existence check: none yet
      .mockResolvedValueOnce(winner); // post-conflict re-read: sibling's row
    convRepo.save.mockRejectedValueOnce({ code: '23505' });

    const result = await service.findOrCreate(asUser(1), asUser(2));

    expect(result).toBe(winner);
    // Exactly one insert was attempted; the second call returned the sibling row.
    expect(convRepo.save).toHaveBeenCalledTimes(1);
  });

  it('recognises 23505 when the code is nested under driverError', async () => {
    const winner = { id: 43 } as Conversation;
    convRepo.findOne.mockResolvedValueOnce(null).mockResolvedValueOnce(winner);
    convRepo.save.mockRejectedValueOnce({ driverError: { code: '23505' } });

    const result = await service.findOrCreate(asUser(1), asUser(2));

    expect(result).toBe(winner);
  });

  it('propagates a non-unique-violation save error instead of swallowing it', async () => {
    // A blanket catch would hide real failures (connection drop, NOT NULL, etc.)
    // and then throw a misleading "Failed to find or create" after a pointless
    // re-read. Only 23505 is a benign race; everything else must surface.
    convRepo.findOne.mockResolvedValueOnce(null);
    const dbError = Object.assign(new Error('connection terminated'), {
      code: '08006',
    });
    convRepo.save.mockRejectedValueOnce(dbError);

    await expect(service.findOrCreate(asUser(1), asUser(2))).rejects.toBe(
      dbError,
    );
    // No recovery re-read for a non-race error: only the existence check ran.
    expect(convRepo.findOne).toHaveBeenCalledTimes(1);
  });
});
