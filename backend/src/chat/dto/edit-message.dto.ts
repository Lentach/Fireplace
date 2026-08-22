import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import { MAX_ENVELOPES_PER_MESSAGE, SendEnvelopeDto } from './chat.dto';

export class EditMessageDto {
  @IsInt()
  @IsPositive()
  messageId: number;

  /** Plaintext placeholder ('[encrypted]') — server never stores real plaintext. */
  @IsOptional()
  @IsString()
  content?: string;

  /**
   * New base64-encoded Signal Protocol ciphertext for the edited message.
   *
   * Non-empty WHEN PRESENT: a null/empty ciphertext would brick the row into a
   * permanently undecryptable '[encrypted]' placeholder for both parties. It is
   * required only for a LEGACY single-ciphertext edit — an envelope-bearing
   * edit (spec §5.7) carries one ciphertext PER DEVICE and none at top level,
   * so exactly one of the two shapes must be present.
   */
  @ValidateIf((o: EditMessageDto) => !o.envelopes?.length)
  @IsString()
  @IsNotEmpty()
  @MaxLength(65536)
  encryptedContent?: string;

  /**
   * Per-device edited ciphertexts (spec §5.7 + §12 amendment (xxx)): a full
   * re-fan, one ciphertext per recipient device AND per sender's other device.
   * Presence makes this a NEW-MODEL edit, exactly as it does for a send: the
   * row's legacy `encryptedContent` column is left alone (amendment (xxxii))
   * and every ciphertext lands in `message_envelopes`.
   *
   * The editing device is the PRODUCER of these ciphertexts and therefore gets
   * no envelope of its own — `self_envelope_for_origin_device` is keyed on it.
   */
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_ENVELOPES_PER_MESSAGE)
  @ValidateNested({ each: true })
  @Type(() => SendEnvelopeDto)
  envelopes?: SendEnvelopeDto[];

  /**
   * The sender's and recipient's DAK-signed device-list versions at encrypt
   * time. An edit runs the SAME freshness check as a send (spec §5.7 "same
   * staleness bounce as §5.2", pinned by amendment (xxxi)), and these are the
   * stamps that check consumes; an absent stamp for an ENROLLED party counts
   * as a mismatch, so a client cannot skip the check by omitting the field.
   */
  @IsOptional()
  @IsInt()
  @IsPositive()
  senderListVersion?: number;

  @IsOptional()
  @IsInt()
  @IsPositive()
  recipientListVersion?: number;
}
