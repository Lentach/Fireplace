import { MessagesService } from './messages.service';
import { Repository } from 'typeorm';
import { Message } from './message.entity';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';

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
  let qb: any;

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
});
