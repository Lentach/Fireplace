import { validate } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { SendMessageDto } from './chat.dto';

function createDto(data: Partial<SendMessageDto>): SendMessageDto {
  return plainToInstance(SendMessageDto, data);
}

describe('SendMessageDto', () => {
  describe('unencrypted messages', () => {
    it('should accept valid TEXT message', async () => {
      const dto = createDto({ recipientId: 1, content: 'Hello!' });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should reject empty content for TEXT', async () => {
      const dto = createDto({ recipientId: 1, content: '' });
      const errors = await validate(dto);
      expect(errors.length).toBeGreaterThan(0);
    });

    it('should accept empty content for VOICE', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '',
        messageType: 'VOICE',
        mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/a.m4a',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept empty content for PING', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '',
        messageType: 'PING',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });
  });

  describe('encrypted messages (E2E)', () => {
    it('should accept encrypted message without content validation', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:base64ciphertext==',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept encrypted message with empty content', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '',
        encryptedContent: '3:base64ciphertext==',
      });
      const errors = await validate(dto);
      // encryptedContent present -> content validation skipped
      expect(errors).toHaveLength(0);
    });

    it('should accept encrypted PING (no content, no mediaUrl)', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:pingCipher==',
        // No messageType or mediaUrl — hidden in envelope
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept encrypted VOICE (no mediaUrl in payload)', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:voiceCipher==',
        // mediaUrl is inside the encrypted envelope, not in WS payload
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept encrypted IMAGE (no mediaUrl in payload)', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:imageCipher==',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should reject non-Cloudinary mediaUrl even with encryptedContent', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        mediaUrl: 'https://evil.com/malware.exe',
      });
      const errors = await validate(dto);
      expect(errors.length).toBeGreaterThan(0);
      const mediaUrlError = errors.find((e) => e.property === 'mediaUrl');
      expect(mediaUrlError).toBeDefined();
    });

    it('should accept Cloudinary mediaUrl with encryptedContent', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/voice/abc.m4a',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });
  });

  describe('mediaUrl validation', () => {
    it('should reject non-Cloudinary URL', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '',
        messageType: 'VOICE',
        mediaUrl: 'https://evil.com/payload.mp3',
      });
      const errors = await validate(dto);
      const mediaUrlError = errors.find((e) => e.property === 'mediaUrl');
      expect(mediaUrlError).toBeDefined();
    });

    it('should accept valid Cloudinary image URL', async () => {
      const dto = createDto({
        recipientId: 1,
        content: 'image caption',
        messageType: 'IMAGE',
        mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/photos/pic.jpg',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept null/undefined mediaUrl', async () => {
      const dto = createDto({
        recipientId: 1,
        content: 'hello',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });
  });
});
