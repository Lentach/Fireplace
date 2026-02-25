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
    expect(repo.find).toHaveBeenCalledWith(
      expect.objectContaining({ skip: 0 }),
    );
  });
});
