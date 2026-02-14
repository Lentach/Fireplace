import { IsInt } from 'class-validator';

export class DeleteConversationOnlyDto {
  @IsInt()
  conversationId: number;
}
