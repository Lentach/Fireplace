// backend/src/contact/contact.service.spec.ts
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ContactMessage } from './contact-message.entity';
import { ContactPushSubscription } from './contact-push-subscription.entity';
import { ContactService } from './contact.service';
import { PushNotificationsService } from '../push-notifications/push-notifications.service';

interface MockContactRepo {
  create: jest.Mock;
  save: jest.Mock;
  find: jest.Mock;
}
interface MockSubRepo {
  find: jest.Mock;
  upsert: jest.Mock;
  delete: jest.Mock;
}
interface MockPushService {
  notifyContact: jest.Mock;
  sendRawWebPush: jest.Mock;
}
const mockRepo = (): MockContactRepo => ({
  create: jest.fn((v) => v),
  save: jest.fn().mockResolvedValue(undefined),
  find: jest.fn().mockResolvedValue([]),
});
const mockSubRepo = (): MockSubRepo => ({
  find: jest.fn().mockResolvedValue([]),
  upsert: jest.fn().mockResolvedValue(undefined),
  delete: jest.fn().mockResolvedValue(undefined),
});
const mockPush = (): MockPushService => ({
  notifyContact: jest.fn().mockResolvedValue(undefined),
  sendRawWebPush: jest.fn().mockResolvedValue('ok'),
});

const KEY = 'a'.repeat(64);

// create() fires the inbox fan-out without awaiting it — flush microtasks +
// one macrotask so the fire-and-forget chain settles before asserting.
function flushAsync(): Promise<void> {
  // executor form: this repo's tsconfig lib predates ES2024's withResolvers
  return new Promise<void>((resolve) => setImmediate(resolve));
}

describe('ContactService', () => {
  let service: ContactService;
  let repo: MockContactRepo;
  let subRepo: MockSubRepo;
  let push: MockPushService;
  const envBackup = {
    notify: process.env.CONTACT_NOTIFY_USER_ID,
    key: process.env.CONTACT_INBOX_KEY,
  };

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        ContactService,
        { provide: getRepositoryToken(ContactMessage), useFactory: mockRepo },
        {
          provide: getRepositoryToken(ContactPushSubscription),
          useFactory: mockSubRepo,
        },
        { provide: PushNotificationsService, useFactory: mockPush },
      ],
    }).compile();

    service = module.get(ContactService);
    repo = module.get(getRepositoryToken(ContactMessage));
    subRepo = module.get(getRepositoryToken(ContactPushSubscription));
    push = module.get(PushNotificationsService);
    delete process.env.CONTACT_NOTIFY_USER_ID;
    process.env.CONTACT_INBOX_KEY = KEY;
  });

  afterEach(() => {
    for (const [env, val] of [
      ['CONTACT_NOTIFY_USER_ID', envBackup.notify],
      ['CONTACT_INBOX_KEY', envBackup.key],
    ] as const) {
      if (val === undefined) delete process.env[env];
      else process.env[env] = val;
    }
  });

  it('persists the message row', async () => {
    await service.create('hello', 'me@example.com');
    expect(repo.save).toHaveBeenCalledWith({
      message: 'hello',
      replyTo: 'me@example.com',
    });
  });

  it('skips the account ping when CONTACT_NOTIFY_USER_ID is unset', async () => {
    await service.create('hello', null);
    expect(push.notifyContact).not.toHaveBeenCalled();
  });

  it('pings the configured owner account after saving', async () => {
    process.env.CONTACT_NOTIFY_USER_ID = '7';
    await service.create('hello', null);
    expect(push.notifyContact).toHaveBeenCalledWith(7);
  });

  it('a failing push never fails the submission', async () => {
    process.env.CONTACT_NOTIFY_USER_ID = '7';
    push.notifyContact.mockRejectedValue(new Error('push down'));
    await expect(service.create('hello', null)).resolves.toBeUndefined();
    expect(repo.save).toHaveBeenCalled();
  });

  describe('inboxKeyValid', () => {
    it('accepts the exact configured key', () => {
      expect(service.inboxKeyValid(KEY)).toBe(true);
    });

    it.each([
      ['wrong key', 'b'.repeat(64)],
      ['prefix of the key', KEY.slice(0, 32)],
      ['empty', ''],
      ['undefined', undefined],
    ])('rejects %s', (_label, candidate) => {
      expect(service.inboxKeyValid(candidate)).toBe(false);
    });

    it('rejects everything when the env key is unset or too short', () => {
      delete process.env.CONTACT_INBOX_KEY;
      expect(service.inboxKeyValid(KEY)).toBe(false);
      process.env.CONTACT_INBOX_KEY = 'short';
      expect(service.inboxKeyValid('short')).toBe(false);
    });
  });

  describe('inbox notifications', () => {
    const sub = (id: number) => ({
      id,
      endpoint: `https://push.example/${id}`,
      p256dh: 'p',
      auth: 'a',
    });

    it('fans out a content preview to every subscription', async () => {
      subRepo.find.mockResolvedValue([sub(1), sub(2)]);
      await service.create('the message body', null);
      // create() fires notifyInbox without awaiting — flush microtasks
      await flushAsync();
      expect(push.sendRawWebPush).toHaveBeenCalledTimes(2);
      const [, body] = push.sendRawWebPush.mock.calls[0];
      expect(body.body).toBe('the message body');
      expect(body.url).toBe(`/contact/inbox?key=${KEY}`);
    });

    it('truncates long previews to ~120 chars', async () => {
      subRepo.find.mockResolvedValue([sub(1)]);
      await service.create('x'.repeat(500), null);
      await flushAsync();
      const [, body] = push.sendRawWebPush.mock.calls[0];
      expect(body.body).toHaveLength(120);
      expect(body.body.endsWith('…')).toBe(true);
    });

    it('prunes subscriptions the push service reports stale', async () => {
      subRepo.find.mockResolvedValue([sub(1), sub(2)]);
      push.sendRawWebPush
        .mockResolvedValueOnce('stale')
        .mockResolvedValueOnce('ok');
      await service.create('hello', null);
      await flushAsync();
      expect(subRepo.delete).toHaveBeenCalledWith({ id: 1 });
      expect(subRepo.delete).toHaveBeenCalledTimes(1);
    });
  });

  it('subscribe upserts on endpoint', async () => {
    await service.subscribe('https://push.example/1', 'p', 'a');
    expect(subRepo.upsert).toHaveBeenCalledWith(
      { endpoint: 'https://push.example/1', p256dh: 'p', auth: 'a' },
      ['endpoint'],
    );
  });
});
