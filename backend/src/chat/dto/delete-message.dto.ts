import { IsNumber, IsPositive, IsIn } from 'class-validator';

export class DeleteMessageDto {
  @IsNumber()
  @IsPositive()
  messageId: number;

  /** 'for_me' = hide only for current user; 'for_everyone' = hard delete (sender only) */
  @IsIn(['for_me', 'for_everyone'])
  mode: 'for_me' | 'for_everyone';
}
