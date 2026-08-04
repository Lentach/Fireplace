import { IsInt, IsPositive } from 'class-validator';

export class DeleteConversationOnlyDto {
  @IsInt()
  @IsPositive()
  conversationId: number;
}
