import { MessagesService } from './messages.service';
import { Repository } from 'typeorm';
import { Message, MessageDeliveryStatus } from './message.entity';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';
import { MESSAGE_NOT_EXPIRED_SQL } from './message-expiry.util';
import { MediaCleanupService } from '../media/media-cleanup.service';

/** Every MessagesService module needs this since the hard-delete rule. */
const mediaCleanupMock = () => ({
  provide: MediaCleanupService,
  useValue: { deleteMediaFile: jest.fn().mockResolvedValue(undefined) },
});

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
        mediaCleanupMock(),
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
        mediaCleanupMock(),
      ],
    }).compile();
    service = module.get(MessagesService);
  });

  it('returns correct unreadTotal, unreadConversationIds, and per-conv counts', async () => {
    const result = await service.getUnreadSummaryForUser(42);

    expect(result.unreadTotal).toBe(8);
    expect(result.unreadConversationIds).toEqual(
      expect.arrayContaining([10, 20]),
    );
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
    expect(qb.andWhere).toHaveBeenCalledWith('m."deliveryStatus" != :status', {
      status: MessageDeliveryStatus.READ,
    });
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
        mediaCleanupMock(),
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

    const result = await service.editMessage(5, 1, {
      content: 'new plaintext',
    });

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
    [
      ...(qb.where.mock.calls as unknown[][]),
      ...(qb.andWhere.mock.calls as unknown[][]),
    ].map((c) => String(c[0]));

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
        mediaCleanupMock(),
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
      {
        id: 1,
        hiddenByUserIds: '5,42,7',
        expiresAt: null,
        disappearAfterSeconds: null,
        createdAt: new Date(),
      },
      {
        id: 2,
        hiddenByUserIds: '5,7',
        expiresAt: null,
        disappearAfterSeconds: null,
        createdAt: new Date(),
      },
      {
        id: 3,
        hiddenByUserIds: null,
        expiresAt: null,
        disappearAfterSeconds: null,
        createdAt: new Date(),
      },
    ]);

    expect(await service.findServedMessageIds([1, 2, 3], 42)).toEqual([2, 3]);
  });

  it('drops expired rows but keeps a disappearing message still inside its unread window', async () => {
    const now = Date.now();
    qb.getRawMany.mockResolvedValue([
      // Deadline already passed.
      {
        id: 1,
        hiddenByUserIds: null,
        expiresAt: new Date(now - 1000),
        disappearAfterSeconds: 60,
        createdAt: new Date(now - 5000),
      },
      // Read-mode, never read, sent two days ago → past the 1-day unread cap.
      {
        id: 2,
        hiddenByUserIds: null,
        expiresAt: null,
        disappearAfterSeconds: 60,
        createdAt: new Date(now - 2 * DAY_MS),
      },
      // Read-mode, never read, sent a minute ago → still live despite the
      // 60-second timer: the clock only starts when the recipient reads.
      {
        id: 3,
        hiddenByUserIds: null,
        expiresAt: null,
        disappearAfterSeconds: 60,
        createdAt: new Date(now - 60 * 1000),
      },
      // Deadline in the future.
      {
        id: 4,
        hiddenByUserIds: null,
        expiresAt: new Date(now + DAY_MS),
        disappearAfterSeconds: null,
        createdAt: new Date(now - 5000),
      },
    ]);

    expect(await service.findServedMessageIds([1, 2, 3, 4], 42)).toEqual([
      3, 4,
    ]);
  });

  it('never queries for an empty or non-positive id set', async () => {
    expect(await service.findServedMessageIds([], 42)).toEqual([]);
    expect(await service.findServedMessageIds([0, -3, 1.5, NaN], 42)).toEqual(
      [],
    );
    expect(createQueryBuilder).not.toHaveBeenCalled();
  });

  it('de-duplicates the requested ids', async () => {
    await service.findServedMessageIds([4, 4, 9, 4], 42);

    expect(qb.where).toHaveBeenCalledWith('m.id IN (:...ids)', { ids: [4, 9] });
  });
});

describe('MessagesService.hideMessageForUser', () => {
  let service: MessagesService;
  let repo: {
    findOne: jest.Mock;
    query: jest.Mock<Promise<unknown>, [string, unknown[]]>;
    delete: jest.Mock;
  };
  let mediaCleanup: { deleteMediaFile: jest.Mock };

  const conv = (a: number, b: number) => ({
    id: 10,
    userOne: { id: a },
    userTwo: { id: b },
  });

  /** repo.query() returns the [rows, rowCount] tuple for UPDATE…RETURNING. */
  const returning = (hiddenByUserIds: string | null) => [
    [{ hiddenByUserIds }],
    1,
  ];

  beforeEach(async () => {
    repo = {
      findOne: jest.fn(),
      query: jest
        .fn<Promise<unknown>, [string, unknown[]]>()
        .mockResolvedValue(returning('1')),
      delete: jest.fn().mockResolvedValue({ affected: 1 }),
    };
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        { provide: getRepositoryToken(Message), useValue: repo },
        mediaCleanupMock(),
      ],
    }).compile();
    service = module.get(MessagesService);
    mediaCleanup = module.get(MediaCleanupService);
  });

  it('NEVER deletes when only one participant hid the row', async () => {
    // THE guard of this feature: the other participant still reads the
    // message. Weakening every() to some(), or hardcoding a count, must turn
    // this red.
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: null,
      mediaUrl: 'https://example.com/media/msgs/a.bin',
      conversation: conv(1, 2),
    });
    repo.query.mockResolvedValue(returning('1'));

    expect(await service.hideMessageForUser(7, 1)).toBe(true);

    expect(repo.delete).not.toHaveBeenCalled();
    expect(mediaCleanup.deleteMediaFile).not.toHaveBeenCalled();
  });

  it('hard-deletes once EVERY participant hid, media then replies then row', async () => {
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: '1',
      mediaUrl: 'https://example.com/media/msgs/a.bin',
      conversation: conv(1, 2),
    });
    repo.query
      .mockResolvedValueOnce(returning('1,2')) // hidden append
      .mockResolvedValueOnce([[], 0]); // reply detach

    expect(await service.hideMessageForUser(7, 2)).toBe(true);

    expect(mediaCleanup.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/a.bin',
    );
    expect(repo.delete).toHaveBeenCalledWith({ id: 7 });
    // Reply pointers detach (self-FK has no ON DELETE) and media unlinks
    // BEFORE the row goes away.
    const detachCall = repo.query.mock.calls.find((c) =>
      c[0].includes('reply_to_message_id'),
    );
    expect(detachCall).toBeDefined();
    expect(detachCall![0]).toContain('SET reply_to_message_id = NULL');
    const deleteOrder = repo.delete.mock.invocationCallOrder[0];
    expect(
      mediaCleanup.deleteMediaFile.mock.invocationCallOrder[0],
    ).toBeLessThan(deleteOrder);
    const detachOrder =
      repo.query.mock.invocationCallOrder[repo.query.mock.calls.length - 1];
    expect(detachOrder).toBeLessThan(deleteOrder);
  });

  it('appends via a single atomic UPDATE with quoted "hiddenByUserIds"', async () => {
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: null,
      mediaUrl: null,
      conversation: conv(1, 2),
    });

    await service.hideMessageForUser(7, 1);

    const [sql, params] = repo.query.mock.calls[0];
    expect(sql).toContain('"hiddenByUserIds"');
    expect(sql).toContain('RETURNING');
    expect(params).toEqual([7, '1']);
  });

  it('skips media unlink when the row has none', async () => {
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: '2',
      mediaUrl: null,
      conversation: conv(1, 2),
    });
    repo.query
      .mockResolvedValueOnce(returning('2,1'))
      .mockResolvedValueOnce([[], 0]);

    await service.hideMessageForUser(7, 1);

    expect(mediaCleanup.deleteMediaFile).not.toHaveBeenCalled();
    expect(repo.delete).toHaveBeenCalledWith({ id: 7 });
  });

  it('is idempotent for an already-hidden user and still heals a fully-hidden legacy row', async () => {
    // Pre-fix data: both participants hid before the rule shipped. A repeat
    // call must not re-append (no UPDATE on hiddenByUserIds) but MUST
    // hard-delete.
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: '1,2',
      mediaUrl: null,
      conversation: conv(1, 2),
    });
    repo.query.mockResolvedValue([[], 0]); // only the reply detach runs

    expect(await service.hideMessageForUser(7, 1)).toBe(true);

    const appendCalls = repo.query.mock.calls.filter((c: unknown[]) =>
      String(c[0]).includes('"hiddenByUserIds"'),
    );
    expect(appendCalls).toHaveLength(0);
    expect(repo.delete).toHaveBeenCalledWith({ id: 7 });
  });

  it('returns false when the message is gone', async () => {
    repo.findOne.mockResolvedValue(null);

    expect(await service.hideMessageForUser(7, 1)).toBe(false);
    expect(repo.query).not.toHaveBeenCalled();
    expect(repo.delete).not.toHaveBeenCalled();
  });

  it('returns false when the row vanishes between read and append', async () => {
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: null,
      mediaUrl: null,
      conversation: conv(1, 2),
    });
    repo.query.mockResolvedValue([[], 0]); // UPDATE matched nothing

    expect(await service.hideMessageForUser(7, 1)).toBe(false);
    expect(repo.delete).not.toHaveBeenCalled();
  });

  it('never deletes when the conversation relation is missing (fail closed)', async () => {
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: '2',
      mediaUrl: null,
      conversation: null,
    });
    repo.query.mockResolvedValue(returning('2,1'));

    expect(await service.hideMessageForUser(7, 1)).toBe(true);
    expect(repo.delete).not.toHaveBeenCalled();
  });

  it('uses the actual participant set — a self-conversation deletes after its single hide', async () => {
    // Guards against hardcoding "2 participants": the set is derived from
    // the conversation relation, deduplicated.
    repo.findOne.mockResolvedValue({
      id: 7,
      hiddenByUserIds: null,
      mediaUrl: null,
      conversation: conv(5, 5),
    });
    repo.query
      .mockResolvedValueOnce(returning('5'))
      .mockResolvedValueOnce([[], 0]);

    expect(await service.hideMessageForUser(7, 5)).toBe(true);
    expect(repo.delete).toHaveBeenCalledWith({ id: 7 });
  });
});

describe('MessagesService.deleteById', () => {
  let service: MessagesService;
  let repo: {
    findOne: jest.Mock;
    query: jest.Mock<Promise<unknown>, [string, unknown[]]>;
    remove: jest.Mock;
  };

  beforeEach(async () => {
    repo = {
      findOne: jest.fn(),
      query: jest
        .fn<Promise<unknown>, [string, unknown[]]>()
        .mockResolvedValue([[], 0]),
      remove: jest.fn().mockImplementation((m) => Promise.resolve(m)),
    };
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        { provide: getRepositoryToken(Message), useValue: repo },
        mediaCleanupMock(),
      ],
    }).compile();
    service = module.get(MessagesService);
  });

  it('detaches replies BEFORE removing the row (self-FK has no ON DELETE)', async () => {
    repo.findOne.mockResolvedValue({
      id: 9,
      sender: { id: 1 },
      conversation: { id: 10 },
    });

    expect(await service.deleteById(9, 1)).not.toBeNull();

    const [sql, params] = repo.query.mock.calls[0];
    expect(sql).toContain('SET reply_to_message_id = NULL');
    expect(params).toEqual([9]);
    expect(repo.query.mock.invocationCallOrder[0]).toBeLessThan(
      repo.remove.mock.invocationCallOrder[0],
    );
  });

  it('does not touch replies when the caller is not the sender', async () => {
    repo.findOne.mockResolvedValue({
      id: 9,
      sender: { id: 99 },
      conversation: { id: 10 },
    });

    expect(await service.deleteById(9, 1)).toBeNull();
    expect(repo.query).not.toHaveBeenCalled();
    expect(repo.remove).not.toHaveBeenCalled();
  });
});
