import { IsInt, IsOptional, IsString, MaxLength } from 'class-validator';

export class EditMessageDto {
  @IsInt()
  messageId: number;

  /** Plaintext placeholder ('[encrypted]') — server never stores real plaintext. */
  @IsOptional()
  @IsString()
  content?: string;

  /** New base64-encoded Signal Protocol ciphertext for the edited message. */
  @IsOptional()
  @IsString()
  @MaxLength(20000)
  encryptedContent?: string;
}
