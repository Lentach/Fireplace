import {
  IsNumber,
  IsString,
  IsPositive,
  MinLength,
  MaxLength,
  IsOptional,
  Min,
  Max,
  Matches,
  ValidateIf,
  IsIn,
} from 'class-validator';
import {
  DISAPPEARING_MAX_SECONDS,
  DISAPPEARING_MIN_SECONDS,
} from '../../messages/disappearing.constants';
import { MessageType } from '../../messages/message.entity';

/** Cloudinary (https only) or self-hosted media under MEDIA_BASE_URL — prevents SSRF */
const _mediaOriginEscaped = (
  process.env.MEDIA_BASE_URL ?? 'http://localhost:3000'
).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// The self-hosted branch is anchored to a single `avatars|msgs/<filename>.<ext>`
// segment (no `/`, so no `..` traversal) — `mediaUrl` is later turned into a
// filesystem path and unlinked (H-02). The `$` anchor applies to both branches.
export const MEDIA_URL_REGEX = new RegExp(
  `^(https://res\\.cloudinary\\.com/[a-zA-Z0-9_-]+/(video|image|raw)/upload/.+|${_mediaOriginEscaped}/media/(avatars|msgs)/[A-Za-z0-9_-]+\\.[A-Za-z0-9]+)$`,
);

export class SendMessageDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @IsString()
  @ValidateIf(
    (o) => !o.encryptedContent && !['VOICE', 'PING'].includes(o?.messageType),
  )
  @MinLength(1, { message: 'Message cannot be empty' })
  @MaxLength(5000, { message: 'Message cannot exceed 5000 characters' })
  content: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(10000)
  encryptedContent?: string; // Base64-encoded Signal Protocol ciphertext

  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Min(DISAPPEARING_MIN_SECONDS)
  @Max(DISAPPEARING_MAX_SECONDS)
  expiresIn?: number; // disappearing TTL frozen at send (read-based countdown)

  @IsOptional()
  @IsString()
  tempId?: string; // Client-generated ID for optimistic message matching

  @IsOptional()
  @IsString()
  @IsIn(Object.values(MessageType))
  messageType?: string; // TEXT | PING | IMAGE | VOICE | GIF | FILE

  @IsOptional()
  @IsString()
  @ValidateIf((o) => o.mediaUrl != null && o.mediaUrl !== '')
  @Matches(MEDIA_URL_REGEX, {
    message: 'mediaUrl must be a valid Cloudinary or self-hosted media URL',
  })
  mediaUrl?: string; // Validated self-hosted or legacy Cloudinary media URL

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

const REACTION_EMOJI_REGEX =
  /^(?:\p{Extended_Pictographic}(?:\uFE0F|\p{Emoji_Modifier})?(?:\u200D\p{Extended_Pictographic}(?:\uFE0F|\p{Emoji_Modifier})?)*|\p{Regional_Indicator}{2}|[0-9#*]\uFE0F?\u20E3)$/u;

export class AddReactionDto {
  @IsNumber()
  @IsPositive()
  messageId: number;

  @IsString()
  @MaxLength(32)
  @Matches(REACTION_EMOJI_REGEX, {
    message: 'emoji must be a single emoji grapheme',
  })
  emoji: string;
}

export class RemoveReactionDto {
  @IsNumber()
  @IsPositive()
  messageId: number;

  @IsString()
  @MaxLength(32)
  @Matches(REACTION_EMOJI_REGEX, {
    message: 'emoji must be a single emoji grapheme',
  })
  emoji: string;
}
