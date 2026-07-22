// backend/src/contact/contact.service.spec.ts
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ContactMessage } from './contact-message.entity';
import { ContactService } from './contact.service';
import { PushNotificationsService } from '../push-notifications/push-notifications.service';

interface MockContactRepo {
  create: jest.Mock;
  save: jest.Mock;
}
interface MockPushService {
  notifyContact: jest.Mock;
}
const mockRepo = (): MockContactRepo => ({
  create: jest.fn((v) => v),
  save: jest.fn().mockResolvedValue(undefined),
});
const mockPush = (): MockPushService => ({
  notifyContact: jest.fn().mockResolvedValue(undefined),
});

describe('ContactService', () => {
  let service: ContactService;
  let repo: MockContactRepo;
  let push: MockPushService;
  const envBackup = process.env.CONTACT_NOTIFY_USER_ID;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        ContactService,
        { provide: getRepositoryToken(ContactMessage), useFactory: mockRepo },
        { provide: PushNotificationsService, useFactory: mockPush },
      ],
    }).compile();

    service = module.get(ContactService);
    repo = module.get(getRepositoryToken(ContactMessage));
    push = module.get(PushNotificationsService);
  });

  afterEach(() => {
    if (envBackup === undefined) delete process.env.CONTACT_NOTIFY_USER_ID;
    else process.env.CONTACT_NOTIFY_USER_ID = envBackup;
  });

  it('persists the message row', async () => {
    delete process.env.CONTACT_NOTIFY_USER_ID;
    await service.create('hello', 'me@example.com');
    expect(repo.save).toHaveBeenCalledWith({
      message: 'hello',
      replyTo: 'me@example.com',
    });
  });

  it('skips the owner ping when CONTACT_NOTIFY_USER_ID is unset', async () => {
    delete process.env.CONTACT_NOTIFY_USER_ID;
    await service.create('hello', null);
    expect(push.notifyContact).not.toHaveBeenCalled();
  });

  it('pings the configured owner account after saving', async () => {
    process.env.CONTACT_NOTIFY_USER_ID = '7';
    await service.create('hello', null);
    expect(push.notifyContact).toHaveBeenCalledWith(7);
  });

  it('ignores a malformed CONTACT_NOTIFY_USER_ID', async () => {
    process.env.CONTACT_NOTIFY_USER_ID = 'not-a-number';
    await service.create('hello', null);
    expect(push.notifyContact).not.toHaveBeenCalled();
  });

  it('a failing push never fails the submission', async () => {
    process.env.CONTACT_NOTIFY_USER_ID = '7';
    push.notifyContact.mockRejectedValue(new Error('push down'));
    await expect(service.create('hello', null)).resolves.toBeUndefined();
    expect(repo.save).toHaveBeenCalled();
  });
});
