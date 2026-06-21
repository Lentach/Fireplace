// backend/src/secret-notes/secret-notes.controller.spec.ts
import { Test } from '@nestjs/testing';
import { SecretNotesController } from './secret-notes.controller';
import { SecretNotesService } from './secret-notes.service';

const mockService = () => ({
  create: jest.fn(),
  findByToken: jest.fn(),
  revealAndDelete: jest.fn(),
});

const mockUser = { id: 1 };
const mockRes = () => {
  const res: any = {};
  res.send = jest.fn().mockReturnValue(res);
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  res.setHeader = jest.fn().mockReturnValue(res);
  return res;
};

describe('SecretNotesController', () => {
  let controller: SecretNotesController;
  let service: ReturnType<typeof mockService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [SecretNotesController],
      providers: [{ provide: SecretNotesService, useFactory: mockService }],
    }).compile();

    controller = module.get(SecretNotesController);
    service = module.get(SecretNotesService);
  });

  describe('createNote', () => {
    it('returns token for valid request', async () => {
      service.create.mockResolvedValue({ token: 'abc123' });
      const result = await controller.createNote(
        { ciphertext: 'enc', expiresIn: 7200 },
        { user: mockUser },
      );
      expect(result).toEqual({ token: 'abc123' });
      expect(service.create).toHaveBeenCalledWith('enc', 7200, 1);
    });
  });

  describe('getNotePage', () => {
    it('sends HTML when note exists', async () => {
      const future = new Date(Date.now() + 60000);
      service.findByToken.mockResolvedValue({ token: 'tok', expiresAt: future });
      const res = mockRes();
      await controller.getNotePage('tok', res);
      expect(res.send).toHaveBeenCalled();
      const html = res.send.mock.calls[0][0];
      expect(html).toContain('Reveal');
      expect(res.setHeader).toHaveBeenCalledWith(
        'Content-Security-Policy',
        expect.stringContaining("script-src 'nonce-"),
      );
      expect(html).toContain("addEventListener('click', reveal)");
      expect(html).not.toContain('onclick=');
    });

    it('sends destroyed HTML when note not found', async () => {
      service.findByToken.mockResolvedValue(null);
      const res = mockRes();
      await controller.getNotePage('missing', res);
      expect(res.send).toHaveBeenCalled();
      const html = res.send.mock.calls[0][0];
      expect(html).toContain('no longer exists');
    });
  });

  describe('revealNote', () => {
    it('returns ciphertext when note exists', async () => {
      service.revealAndDelete.mockResolvedValue({ ciphertext: 'enc' });
      const res = mockRes();
      await controller.revealNote('tok', res);
      expect(res.json).toHaveBeenCalledWith({ ciphertext: 'enc' });
    });

    it('returns 404 when note gone', async () => {
      service.revealAndDelete.mockResolvedValue(null);
      const res = mockRes();
      await controller.revealNote('missing', res);
      expect(res.status).toHaveBeenCalledWith(404);
    });
  });
});
