import {
  IsNumber,
  IsString,
  IsPositive,
  MinLength,
  MaxLength,
  IsOptional,
  Min,
  IsBoolean,
} from 'class-validator';

export class SendMessageDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @IsString()
  @MinLength(1, { message: 'Message cannot be empty' })
  @MaxLength(5000, { message: 'Message cannot exceed 5000 characters' })
  content: string;
}

export class SendFriendRequestDto {
  @IsString()
  @MinLength(5, { message: 'Email must be at least 5 characters' })
  @MaxLength(255, { message: 'Email cannot exceed 255 characters' })
  recipientEmail: string;
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

export class DeleteConversationDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;
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
  @IsString()
  @MinLength(5, { message: 'Email must be at least 5 characters' })
  @MaxLength(255, { message: 'Email cannot exceed 255 characters' })
  recipientEmail: string;
}

export class UnfriendDto {
  @IsNumber()
  @IsPositive()
  userId: number;
}

export class UpdateActiveStatusDto {
  @IsBoolean()
  activeStatus: boolean;
}
