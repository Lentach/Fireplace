import { BadRequestException } from '@nestjs/common';
import { IsNumber, IsPositive, IsString, MinLength } from 'class-validator';
import { validateDto } from './dto.validator';
import { SendMessageDto } from '../dto/chat.dto';

class SimpleDto {
  @IsNumber()
  @IsPositive()
  id: number;

  @IsString()
  @MinLength(2)
  name: string;
}

describe('validateDto', () => {
  it('should return validated instance for valid data', () => {
    const data = { id: 1, name: 'Alice' };
    const result = validateDto(SimpleDto, data);
    expect(result).toBeInstanceOf(SimpleDto);
    expect(result.id).toBe(1);
    expect(result.name).toBe('Alice');
  });

  it('should accept numeric strings when they parse to valid numbers', () => {
    const data = { id: 42, name: 'Bob' };
    const result = validateDto(SimpleDto, data);
    expect(result.id).toBe(42);
    expect(result.name).toBe('Bob');
  });

  it('should throw BadRequestException for invalid data', () => {
    const data = { id: -1, name: 'X' };
    expect(() => validateDto(SimpleDto, data)).toThrow(BadRequestException);
    expect(() => validateDto(SimpleDto, data)).toThrow(/Validation failed/);
  });

  it('should throw for missing required fields', () => {
    const data = { id: 1 };
    expect(() => validateDto(SimpleDto, data)).toThrow(BadRequestException);
  });
});

describe('SendMessageDto mediaUrl validation', () => {
  const validVoicePayload = {
    recipientId: 1,
    content: '',
    messageType: 'VOICE',
    mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/voice-messages/abc.m4a',
    mediaDuration: 5,
  };

  it('should accept valid Cloudinary video URL', () => {
    const result = validateDto(SendMessageDto, validVoicePayload);
    expect(result.mediaUrl).toBe(validVoicePayload.mediaUrl);
  });

  it('should accept valid Cloudinary image URL', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/folder/photo.jpg',
    };
    const result = validateDto(SendMessageDto, data);
    expect(result.mediaUrl).toBe(data.mediaUrl);
  });

  it('should reject non-allowlisted mediaUrl', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'https://evil.com/malicious.mp3',
    };
    expect(() => validateDto(SendMessageDto, data)).toThrow(BadRequestException);
    expect(() => validateDto(SendMessageDto, data)).toThrow(
      /self-hosted media URL/,
    );
  });

  it('should accept empty or absent mediaUrl', () => {
    const textPayload = { recipientId: 1, content: 'Hello' };
    const result = validateDto(SendMessageDto, textPayload);
    expect(result.mediaUrl).toBeUndefined();
  });

  it('should accept null mediaUrl (ValidateIf skips null)', () => {
    const data = { ...validVoicePayload, mediaUrl: null };
    expect(() => validateDto(SendMessageDto, data)).not.toThrow();
  });

  it('should accept empty string mediaUrl (ValidateIf skips empty string)', () => {
    const data = { ...validVoicePayload, mediaUrl: '' };
    expect(() => validateDto(SendMessageDto, data)).not.toThrow();
  });

  it('should reject HTTP (non-HTTPS) Cloudinary URL', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'http://res.cloudinary.com/demo/video/upload/v1/voice.m4a',
    };
    expect(() => validateDto(SendMessageDto, data)).toThrow(BadRequestException);
    expect(() => validateDto(SendMessageDto, data)).toThrow(
      /self-hosted media URL/,
    );
  });

  it('should reject Cloudinary URL missing /upload/ segment', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'https://res.cloudinary.com/demo/video/v1/voice.m4a',
    };
    expect(() => validateDto(SendMessageDto, data)).toThrow(BadRequestException);
    expect(() => validateDto(SendMessageDto, data)).toThrow(
      /self-hosted media URL/,
    );
  });

  it('should accept Cloudinary raw/upload URL (FILE backward compat)', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'https://res.cloudinary.com/demo/raw/upload/v1/file.txt',
    };
    const result = validateDto(SendMessageDto, data);
    expect(result.mediaUrl).toBe(data.mediaUrl);
  });

  it('should accept self-hosted media URL', () => {
    const base = process.env.MEDIA_BASE_URL ?? 'http://localhost:3000';
    const data = {
      ...validVoicePayload,
      mediaUrl: `${base}/media/msgs/uuid.bin`,
    };
    const result = validateDto(SendMessageDto, data);
    expect(result.mediaUrl).toBe(data.mediaUrl);
  });

  it('should reject data: URL', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'data:audio/mp3;base64,AAAAAAA==',
    };
    expect(() => validateDto(SendMessageDto, data)).toThrow(BadRequestException);
    expect(() => validateDto(SendMessageDto, data)).toThrow(
      /self-hosted media URL/,
    );
  });

  it('should reject URL impersonating Cloudinary domain via subdomain', () => {
    const data = {
      ...validVoicePayload,
      mediaUrl: 'https://res.cloudinary.com.evil.com/demo/video/upload/v1/x.mp3',
    };
    expect(() => validateDto(SendMessageDto, data)).toThrow(BadRequestException);
    expect(() => validateDto(SendMessageDto, data)).toThrow(
      /self-hosted media URL/,
    );
  });
});
