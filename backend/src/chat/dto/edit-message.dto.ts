import { IsInt, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export class EditMessageDto {
  @IsInt()
  messageId: number;

  /** Plaintext placeholder ('[encrypted]') — server never stores real plaintext. */
  @IsOptional()
  @IsString()
  content?: string;

  /** New base64-encoded Signal Protocol ciphertext for the edited message.
   * Required + non-empty: a null/empty ciphertext would brick the row into a
   * permanently undecryptable '[encrypted]' placeholder for both parties. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(65536)
  encryptedContent: string;
}
