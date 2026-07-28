import { MessagesService } from './messages.service';
import { Repository } from 'typeorm';
import { Message, MessageDeliveryStatus } from './message.entity';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';
import { MESSAGE_NOT_EXPIRED_SQL } from './message-expiry.util';

type UnreadSummaryQueryBuilder = {
  innerJoin: jest.Mock;
  select: jest.Mock;
  addSelect: jest.Mock;
  where: jest.Mock;
  andWhere: jest.Mock;
  groupBy: jest.Mock;
  getRawMany: jest.Mock;
};

describe('MessagesService.findByConversation', () => {
  let service: MessagesService;
  let repo: jest.Mocked<Repository<Message>>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        {
          provide: getRepositoryToken(Message),
          useValue: { find: jest.fn().mockResolvedValue([]) },
        },
      ],
    }).compile();
    service = module.get(MessagesService);
    repo = module.get(getRepositoryToken(Message));
  });

  it('uses DB-level skip and take when no hiddenByUserId', async () => {
    await service.findByConversation(1, 20, 40);

    expect(repo.find).toHaveBeenCalledWith(
      expect.objectContaining({ take: 20, skip: 40 }),
    );
  });

  it('filters hidden rows and applies client-side offset/limit slicing (oldest-first)', async () => {
    // repo.find is mocked, so it returns rows in the order we supply: newest-first
    // (DESC), mirroring the real query. The service filters rows hidden for the
    // user, then slices(offset, offset+limit) and reverses to oldest-first.
    const rows = [
      { id: 10, hiddenByUserIds: null, createdAt: new Date() },
      { id: 9, hiddenByUserIds: '99', createdAt: new Date() },
      { id: 8, hiddenByUserIds: null, createdAt: new Date() },
      { id: 7, hiddenByUserIds: null, createdAt: new Date() },
      { id: 6, hiddenByUserIds: '1,99,2', createdAt: new Date() },
      { id: 5, hiddenByUserIds: null, createdAt: new Date() },
    ] as unknown as Message[];
    repo.find.mockResolvedValue(rows);

    // limit=2, offset=1, hiddenByUserId=99
    const result = await service.findByConversation(1, 2, 1, 99);

    // With hiddenByUserId, skip=0 and take=fetchLimit (2*3+1+50=57)
    expect(repo.find).toHaveBeenCalledWith(
      expect.objectContaining({ skip: 0, take: 57 }),
    );
    // Hidden rows (9, 6) removed → [10, 8, 7, 5]; slice(1,3) → [8, 7];
    // reverse() → oldest-first [7, 8].
    expect(result.map((m) => m.id)).toEqual([7, 8]);
    expect(result.map((m) => m.id)).not.toContain(9);
    expect(result.map((m) => m.id)).not.toContain(6);
  });
});

describe('MessagesService.getUnreadSummaryForUser', () => {
  let service: MessagesService;
  let qb: UnreadSummaryQueryBuilder;

  beforeEach(async () => {
    qb = {
      innerJoin: jest.fn().mockReturnThis(),
      select: jest.fn().mockReturnThis(),
      addSelect: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      groupBy: jest.fn().mockReturnThis(),
      getRawMany: jest.fn().mockResolvedValue([
        { conversationId: '10', count: '3' },
        { conversationId: '20', count: '5' },
      ]),
    };
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        {
          provide: getRepositoryToken(Message),
          useValue: {
            find: jest.fn().mockResolvedValue([]),
            createQueryBuilder: jest.fn().mockReturnValue(qb),
          },
        },
      ],
    }).compile();
    service = module.get(MessagesService);
  });

  it('returns correct unreadTotal, unreadConversationIds, and per-conv counts', async () => {
    const result = await service.getUnreadSummaryForUser(42);

    expect(result.unreadTotal).toBe(8);
    expect(result.unreadConversationIds).toEqual(expect.arrayContaining([10, 20]));
    expect(result.unreadConversationIds).toHaveLength(2);
    expect(result.countByConversationId.get(10)).toBe(3);
    expect(result.countByConversationId.get(20)).toBe(5);
  });

  it('returns zeros when no unread messages', async () => {
    qb.getRawMany.mockResolvedValue([]);

    const result = await service.getUnreadSummaryForUser(99);

    expect(result.unreadTotal).toBe(0);
    expect(result.unreadConversationIds).toHaveLength(0);
    expect(result.countByConversationId.size).toBe(0);
  });

  it('applies unread query filters before grouping by conversation', async () => {
    await service.getUnreadSummaryForUser(42);

    expect(qb.innerJoin).toHaveBeenCalledWith('m.sender', 's');
    expect(qb.innerJoin).toHaveBeenCalledWith('m.conversation', 'c');
    expect(qb.where).toHaveBeenCalledWith(
      '(c.user_one_id = :userId OR c.user_two_id = :userId)',
      { userId: 42 },
    );
    expect(qb.andWhere).toHaveBeenCalledWith('s.id != :userId', { userId: 42 });
    expect(qb.andWhere).toHaveBeenCalledWith(
      'm."deliveryStatus" != :status',
      { status: MessageDeliveryStatus.READ },
    );
    expect(qb.andWhere).toHaveBeenCalledWith(
      MESSAGE_NOT_EXPIRED_SQL,
      expect.objectContaining({ now: expect.any(Date) }),
    );
    expect(qb.andWhere).toHaveBeenCalledWith(
      expect.stringContaining('"hiddenByUserIds"'),
      { uid: 42 },
    );
    expect(qb.andWhere).toHaveBeenCalledWith(
      expect.stringContaining('NOT LIKE'),
      { uid: 42 },
    );
    expect(qb.groupBy).toHaveBeenCalledWith('m.conversation_id');
  });
});

describe('MessagesService.editMessage', () => {
  let service: MessagesService;
  let repo: jest.Mocked<Repository<Message>>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        {
          provide: getRepositoryToken(Message),
          useValue: {
            findOne: jest.fn(),
            save: jest.fn((m) => Promise.resolve(m)),
          },
        },
      ],
    }).compile();
    service = module.get(MessagesService);
    repo = module.get(getRepositoryToken(Message));
  });

  it('returns null and does not save when caller is not the sender', async () => {
    repo.findOne.mockResolvedValue({
      id: 5,
      sender: { id: 99 },
      content: '[encrypted]',
      encryptedContent: 'old',
    } as unknown as Message);

    const result = await service.editMessage(5, 1, {
      encryptedContent: 'new',
      content: '[encrypted]',
    });

    expect(result).toBeNull();
    expect(repo.save).not.toHaveBeenCalled();
  });

  it('returns null when the message does not exist', async () => {
    repo.findOne.mockResolvedValue(null);

    const result = await service.editMessage(5, 1, { encryptedContent: 'new' });

    expect(result).toBeNull();
    expect(repo.save).not.toHaveBeenCalled();
  });

  it('updates encryptedContent, content and editedAt for the sender and returns the saved row', async () => {
    const existing = {
      id: 5,
      sender: { id: 1 },
      content: 'old plaintext',
      encryptedContent: 'old-cipher',
      editedAt: null,
    } as unknown as Message;
    repo.findOne.mockResolvedValue(existing);

    const before = Date.now();
    const result = await service.editMessage(5, 1, {
      encryptedContent: 'new-cipher',
      content: '[encrypted]',
    });

    expect(repo.save).toHaveBeenCalledTimes(1);
    expect(result).not.toBeNull();
    expect(result!.encryptedContent).toBe('new-cipher');
    expect(result!.content).toBe('[encrypted]');
    expect(result!.editedAt).toBeInstanceOf(Date);
    expect(result!.editedAt!.getTime()).toBeGreaterThanOrEqual(before);
  });

  it('preserves existing encryptedContent when only content is provided', async () => {
    const existing = {
      id: 5,
      sender: { id: 1 },
      content: 'old plaintext',
      encryptedContent: 'old-cipher',
      editedAt: null,
    } as unknown as Message;
    repo.findOne.mockResolvedValue(existing);

    const result = await service.editMessage(5, 1, { content: 'new plaintext' });

    expect(result).not.toBeNull();
    expect(result!.content).toBe('new plaintext');
    // encryptedContent omitted (undefined) → left untouched
    expect(result!.encryptedContent).toBe('old-cipher');
  });

  it('clears encryptedContent when explicitly passed null', async () => {
    const existing = {
      id: 5,
      sender: { id: 1 },
      content: '[encrypted]',
      encryptedContent: 'old-cipher',
      editedAt: null,
    } as unknown as Message;
    repo.findOne.mockResolvedValue(existing);

    const result = await service.editMessage(5, 1, { encryptedContent: null });

    expect(result).not.toBeNull();
    // explicit null (!== undefined) → field is set to null, not skipped
    expect(result!.encryptedContent).toBeNull();
  });
});

describe('MessagesService.findServedMessageIds', () => {
  const DAY_MS = 86400 * 1000;

  type ServedQueryBuilder = {
    innerJoin: jest.Mock;
    select: jest.Mock;
    addSelect: jest.Mock;
    where: jest.Mock;
    andWhere: jest.Mock;
    getRawMany: jest.Mock;
  };

  let service: MessagesService;
  let qb: ServedQueryBuilder;
  let createQueryBuilder: jest.Mock;

  /** Every predicate the built query carries, in one flat list. */
  const predicates = (): string[] =>
    [...qb.where.mock.calls, ...qb.andWhere.mock.calls].map((c) => String(c[0]));

  beforeEach(async () => {
    qb = {
      innerJoin: jest.fn().mockReturnThis(),
      select: jest.fn().mockReturnThis(),
      addSelect: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      getRawMany: jest.fn().mockResolvedValue([]),
    };
    createQueryBuilder = jest.fn(() => qb);
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        {
          provide: getRepositoryToken(Message),
          useValue: { createQueryBuilder },
        },
      ],
    }).compile();
    service = module.get(MessagesService);
  });

  it('reports a message the caller SENT as still served', async () => {
    // The regression this guards: the unread-count queries in this same
    // service all carry `s.id != :userId`. Copying that here would report the
    // user's entire outgoing history as gone and the client would destroy it.
    qb.getRawMany.mockResolvedValue([
      {
        id: 7,
        hiddenByUserIds: null,
        expiresAt: null,
        disappearAfterSeconds: null,
        createdAt: new Date(),
      },
    ]);

    expect(await service.findServedMessageIds([7], 1)).toEqual([7]);
    expect(predicates().join(' ')).not.toMatch(/sender|s\.id|deliveryStatus/);
  });

  it('scopes to conversations the caller participates in', async () => {
    await service.findServedMessageIds([7], 42);

    expect(qb.innerJoin).toHaveBeenCalledWith('m.conversation', 'c');
    expect(qb.andWhere).toHaveBeenCalledWith(
      '(c.user_one_id = :userId OR c.user_two_id = :userId)',
      { userId: 42 },
    );
  });

  it('drops rows the caller hid with "delete for me"', async () => {
    qb.getRawMany.mockResolvedValue([
      { id: 1, hiddenByUserIds: '5,42,7', expiresAt: null, disappearAfterSeconds: null, createdAt: new Date() },
      { id: 2, hiddenByUserIds: '5,7', expiresAt: null, disappearAfterSeconds: null, createdAt: new Date() },
      { id: 3, hiddenByUserIds: null, expiresAt: null, disappearAfterSeconds: null, createdAt: new Date() },
    ]);

    expect(await service.findServedMessageIds([1, 2, 3], 42)).toEqual([2, 3]);
  });

  it('drops expired rows but keeps a disappearing message still inside its unread window', async () => {
    const now = Date.now();
    qb.getRawMany.mockResolvedValue([
      // Deadline already passed.
      { id: 1, hiddenByUserIds: null, expiresAt: new Date(now - 1000), disappearAfterSeconds: 60, createdAt: new Date(now - 5000) },
      // Read-mode, never read, sent two days ago → past the 1-day unread cap.
      { id: 2, hiddenByUserIds: null, expiresAt: null, disappearAfterSeconds: 60, createdAt: new Date(now - 2 * DAY_MS) },
      // Read-mode, never read, sent a minute ago → still live despite the
      // 60-second timer: the clock only starts when the recipient reads.
      { id: 3, hiddenByUserIds: null, expiresAt: null, disappearAfterSeconds: 60, createdAt: new Date(now - 60 * 1000) },
      // Deadline in the future.
      { id: 4, hiddenByUserIds: null, expiresAt: new Date(now + DAY_MS), disappearAfterSeconds: null, createdAt: new Date(now - 5000) },
    ]);

    expect(await service.findServedMessageIds([1, 2, 3, 4], 42)).toEqual([3, 4]);
  });

  it('never queries for an empty or non-positive id set', async () => {
    expect(await service.findServedMessageIds([], 42)).toEqual([]);
    expect(await service.findServedMessageIds([0, -3, 1.5, NaN], 42)).toEqual([]);
    expect(createQueryBuilder).not.toHaveBeenCalled();
  });

  it('de-duplicates the requested ids', async () => {
    await service.findServedMessageIds([4, 4, 9, 4], 42);

    expect(qb.where).toHaveBeenCalledWith('m.id IN (:...ids)', { ids: [4, 9] });
  });
});
