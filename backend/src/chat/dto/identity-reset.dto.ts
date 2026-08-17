import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Starts an account-identity reset ceremony (multi-device spec §6.2).
 *
 * The optional recovery phrase shortens the delay (§6.2.1). It is bounded in
 * length so a hostile payload cannot turn the memory-hard verifier into a
 * denial-of-service lever: a 12-word phrase is far below this cap.
 */
export class ResetIdentityRequestDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  recoveryPhrase?: string;
}

/** Enrolls or replaces the account's recovery phrase (§6.2.1). */
export class SetRecoveryKeyDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  phrase: string;
}
