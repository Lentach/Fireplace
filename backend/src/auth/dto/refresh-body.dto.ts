import { IsNotEmpty, IsString, MinLength } from 'class-validator';

export class RefreshBodyDto {
  @IsString()
  @IsNotEmpty()
  @MinLength(32)
  refresh_token!: string;
}
