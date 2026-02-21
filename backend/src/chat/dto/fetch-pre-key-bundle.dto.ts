import { IsNumber, IsPositive } from 'class-validator';

export class FetchPreKeyBundleDto {
  @IsNumber()
  @IsPositive()
  userId: number;
}
