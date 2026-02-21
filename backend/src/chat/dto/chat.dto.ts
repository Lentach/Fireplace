import {
  IsNumber,
  IsString,
  IsPositive,
  MinLength,
  MaxLength,
  IsOptional,
  Min,
  Matches,
  ValidateIf,
  IsIn,
} from 'class-validator';

/** Cloudinary URL pattern — prevents SSRF/redirect injection */
const CLOUDINARY_URL_REGEX = /^https:\/\/res\.cloudinary\.com\/[a-zA-Z0-9_-]+\/(video|image)\/upload\/.+/;

export class SendMessageDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @IsString()
  @ValidateIf((o) => !o.encryptedContent && !['VOICE', 'PING'].includes(o?.messageType))
  @MinLength(1, { message: 'Message cannot be empty' })
  @MaxLength(5000, { message: 'Message cannot exceed 5000 characters' })
  content: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  encryptedContent?: string; // Base64-encoded Signal Protocol ciphertext

  @IsOptional()
  @IsNumber()
  @IsPositive()
  expiresIn?: number; // seconds until message expires

  @IsOptional()
  @IsString()
  tempId?: string; // Client-generated ID for optimistic message matching

  @IsOptional()
  @IsString()
  messageType?: string; // 'TEXT', 'VOICE', 'PING', etc.

  @IsOptional()
  @IsString()
  @ValidateIf((o) => o.mediaUrl != null && o.mediaUrl !== '')
  @Matches(CLOUDINARY_URL_REGEX, {
    message: 'mediaUrl must be a valid Cloudinary URL (res.cloudinary.com)',
  })
  mediaUrl?: string; // Cloudinary URL for voice/image

  @IsOptional()
  @IsNumber()
  @IsPositive()
  mediaDuration?: number; // duration in seconds

  @IsOptional()
  @IsNumber()
  @IsPositive()
  replyToMessageId?: number; // ID of the message being replied to
}

export class SendFriendRequestDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;
}

export class SearchUsersDto {
  @IsString()
  @Matches(/^[a-zA-Z0-9_]{3,20}#[0-9]{4}$/, {
    message: 'Enter username#tag (e.g. username#1234)',
  })
  handle: string; // username#tag, e.g. ziomek1#1234
}

export class AcceptFriendRequestDto {
  @IsNumber()
  @IsPositive()
  requestId: number;
}

export class RejectFriendRequestDto {
  @IsNumber()
  @IsPositive()
  requestId: number;
}

export class GetMessagesDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  limit?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  offset?: number;
}

export class StartConversationDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;
}

export class UnfriendDto {
  @IsNumber()
  @IsPositive()
  userId: number;
}

export class BlockUserDto {
  @IsNumber()
  @IsPositive()
  userId: number;
}

export * from './clear-chat-history.dto';
export * from './set-disappearing-timer.dto';
export * from './delete-conversation-only.dto';
export * from './delete-message.dto';

const ALLOWED_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

export class AddReactionDto {
  @IsNumber()
  @IsPositive()
  messageId: number;

  @IsString()
  @IsIn(ALLOWED_EMOJIS)
  emoji: string;
}

export class RemoveReactionDto {
  @IsNumber()
  @IsPositive()
  messageId: number;

  @IsString()
  @IsIn(ALLOWED_EMOJIS)
  emoji: string;
}
