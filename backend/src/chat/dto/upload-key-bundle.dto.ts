import { IsNumber, IsPositive, IsString, Min, MinLength } from 'class-validator';

export class UploadKeyBundleDto {
  @IsNumber()
  @IsPositive()
  registrationId: number;

  @IsString()
  @MinLength(1)
  identityPublicKey: string;

  @IsNumber()
  @Min(0)
  signedPreKeyId: number;

  @IsString()
  @MinLength(1)
  signedPreKeyPublic: string;

  @IsString()
  @MinLength(1)
  signedPreKeySignature: string;
}
