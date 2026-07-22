// backend/src/contact/contact.controller.spec.ts
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ContactController } from './contact.controller';
import { ContactService } from './contact.service';

interface MockContactService {
  create: jest.Mock;
  inboxKeyValid: jest.Mock;
  subscribe: jest.Mock;
}
const mockService = (): MockContactService => ({
  create: jest.fn(),
  inboxKeyValid: jest.fn(),
  subscribe: jest.fn(),
});

describe('ContactController', () => {
  let controller: ContactController;
  let service: MockContactService;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [ContactController],
      providers: [{ provide: ContactService, useFactory: mockService }],
    }).compile();

    controller = module.get(ContactController);
    service = module.get(ContactService);
  });

  it('saves a trimmed message with null replyTo when none given', async () => {
    await controller.create({ message: '  hello there  ' });
    expect(service.create).toHaveBeenCalledWith('hello there', null);
  });

  it('subscribe 404s on a bad inbox key (inbox stays invisible)', async () => {
    service.inboxKeyValid.mockReturnValue(false);
    await expect(
      controller.subscribe({ key: 'x'.repeat(32), endpoint: 'e', p256dh: 'p', auth: 'a' }),
    ).rejects.toThrow(NotFoundException);
    expect(service.subscribe).not.toHaveBeenCalled();
  });

  it('subscribe stores the subscription on a valid key', async () => {
    service.inboxKeyValid.mockReturnValue(true);
    await controller.subscribe({ key: 'k'.repeat(32), endpoint: 'e', p256dh: 'p', auth: 'a' });
    expect(service.subscribe).toHaveBeenCalledWith('e', 'p', 'a');
  });

  it('passes a trimmed replyTo through', async () => {
    await controller.create({ message: 'hi', replyTo: ' me@example.com ' });
    expect(service.create).toHaveBeenCalledWith('hi', 'me@example.com');
  });

  it('treats whitespace-only replyTo as absent', async () => {
    await controller.create({ message: 'hi', replyTo: '   ' });
    expect(service.create).toHaveBeenCalledWith('hi', null);
  });

  it('rejects a whitespace-only message', async () => {
    await expect(controller.create({ message: '   ' })).rejects.toThrow(
      BadRequestException,
    );
    expect(service.create).not.toHaveBeenCalled();
  });

  it('silently drops honeypot submissions without saving', async () => {
    await expect(
      controller.create({ message: 'spam', website: 'http://spam.example' }),
    ).resolves.toBeUndefined();
    expect(service.create).not.toHaveBeenCalled();
  });
});
