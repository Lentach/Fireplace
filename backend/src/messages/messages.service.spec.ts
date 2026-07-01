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

  it('uses client-side offset for hidden messages case', async () => {
    const msgs = Array.from({ length: 10 }, (_, i) => ({
      id: i,
      hiddenByUserIds: null,
      createdAt: new Date(),
    })) as unknown as Message[];
    repo.find.mockResolvedValue(msgs);

    await service.findByConversation(1, 5, 0, 99);

    // With hiddenByUserId, skip should be 0 (fetch more, filter client-side)
    // fetchLimit = limit * 3 + offset + 50 = 5 * 3 + 0 + 50 = 65
    expect(repo.find).toHaveBeenCalledWith(
      expect.objectContaining({ skip: 0, take: 65 }),
    );
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
});
