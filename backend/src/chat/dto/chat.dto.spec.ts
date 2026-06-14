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

    it('should accept encrypted VOICE with self-hosted mediaUrl', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:voiceCipher==',
        messageType: 'VOICE',
        mediaUrl: 'http://localhost:3000/media/msgs/voice.bin',
        mediaDuration: 5,
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept encrypted IMAGE with self-hosted mediaUrl', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:imageCipher==',
        messageType: 'IMAGE',
        mediaUrl: 'http://localhost:3000/media/msgs/image.bin',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept encrypted FILE with self-hosted mediaUrl', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:fileCipher==',
        messageType: 'FILE',
        mediaUrl: 'http://localhost:3000/media/msgs/file.bin',
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

    it('should accept self-hosted media URL', async () => {
      const base = process.env.MEDIA_BASE_URL ?? 'http://localhost:3000';
      const dto = createDto({
        recipientId: 1,
        content: 'caption',
        messageType: 'IMAGE',
        mediaUrl: `${base}/media/msgs/abc.bin`,
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should accept Cloudinary raw/upload URL (FILE backward compat)', async () => {
      const dto = createDto({
        recipientId: 1,
        content: 'file.pdf',
        messageType: 'FILE',
        mediaUrl: 'https://res.cloudinary.com/demo/raw/upload/sample.pdf',
      });
      const errors = await validate(dto);
      expect(errors).toHaveLength(0);
    });

    it('should reject arbitrary non-allowlisted URLs', async () => {
      const dto = createDto({
        recipientId: 1,
        content: '',
        messageType: 'VOICE',
        mediaUrl: 'https://evil.com/file.bin',
      });
      const errors = await validate(dto);
      const mediaUrlError = errors.find((e) => e.property === 'mediaUrl');
      expect(mediaUrlError).toBeDefined();
    });
  });

  // H-02: a self-hosted mediaUrl is later turned into a filesystem path and
  // unlinked. The regex must forbid path traversal / nested paths so a crafted
  // mediaUrl cannot delete arbitrary files.
  describe('mediaUrl path-traversal rejection (H-02)', () => {
    const base = process.env.MEDIA_BASE_URL ?? 'http://localhost:3000';

    async function mediaUrlRejected(mediaUrl: string): Promise<boolean> {
      const dto = createDto({
        recipientId: 1,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        messageType: 'FILE',
        mediaUrl,
      });
      const errors = await validate(dto);
      return errors.some((e) => e.property === 'mediaUrl');
    }

    it('rejects ../ escaping the media root', async () => {
      expect(await mediaUrlRejected(`${base}/media/../../../etc/passwd`)).toBe(
        true,
      );
    });

    it('rejects a msgs/.. traversal', async () => {
      expect(await mediaUrlRejected(`${base}/media/msgs/../../etc/passwd`)).toBe(
        true,
      );
    });

    it('rejects nested sub-paths under msgs (extra slashes)', async () => {
      expect(await mediaUrlRejected(`${base}/media/msgs/sub/dir/x.bin`)).toBe(
        true,
      );
    });

    it('still accepts a normal single-segment msgs blob', async () => {
      expect(await mediaUrlRejected(`${base}/media/msgs/a1b2-c3d4.bin`)).toBe(
        false,
      );
    });

    it('still accepts a normal avatar blob', async () => {
      expect(await mediaUrlRejected(`${base}/media/avatars/abc123.jpg`)).toBe(
        false,
      );
    });
  });
});
