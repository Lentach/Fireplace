import { IsBoolean, IsInt, IsOptional, Min, ValidateIf } from 'class-validator';

/**
 * Client reports foreground/tab visibility and which conversation is open so the server
 * can skip push when the user is already viewing that thread (socket still delivers newMessage).
 */
export class PushClientStateDto {
  @IsOptional()
  @ValidateIf((_, v) => v !== undefined && v !== null)
  @IsInt()
  @Min(1)
  activeConversationId?: number | null;

  @IsBoolean()
  clientVisible: boolean;
}
