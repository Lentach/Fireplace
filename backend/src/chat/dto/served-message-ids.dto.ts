import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsInt,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

/** Upper bound per request. The client's local plaintext store is capped at
 *  2000 records and it chunks below this, so a larger batch is a malformed or
 *  hostile caller rather than a real device. */
export const SERVED_MESSAGE_IDS_MAX_BATCH = 500;

/**
 * "Which of these message ids do you still serve me?"
 *
 * [requestId] is echoed back verbatim so the client can match the answer to the
 * batch it asked about. It MUST NOT be interpreted server-side — a client that
 * applied a mismatched answer would purge the wrong plaintext.
 */
export class GetServedMessageIdsDto {
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  requestId: string;

  @IsArray()
  @ArrayNotEmpty()
  @ArrayMaxSize(SERVED_MESSAGE_IDS_MAX_BATCH)
  @IsInt({ each: true })
  @IsPositive({ each: true })
  messageIds: number[];
}
