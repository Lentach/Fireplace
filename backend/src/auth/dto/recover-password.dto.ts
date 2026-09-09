import { IsString, Matches, MaxLength, MinLength } from 'class-validator';
import {
  PASSWORD_MIN_LENGTH,
  PASSWORD_REGEX,
  PASSWORD_REGEX_MESSAGE,
} from '../password.constants';

/**
 * `POST /auth/recover` — the recovery phrase as a credential (multi-device
 * spec §12 amendment (lxxxii) clause 2). Same identifier grammar as login,
 * same phrase bound as the WS ceremony DTOs, same password rules as register.
 */
export class RecoverPasswordDto {
  @IsString()
  @MinLength(3)
  @MaxLength(25)
  @Matches(/^[a-zA-Z0-9_]+(#[0-9]{4})?$/, {
    message: 'Use username or username#tag (e.g. john#0427)',
  })
  identifier: string;

  @IsString()
  @MinLength(1)
  @MaxLength(256)
  phrase: string;

  @MinLength(PASSWORD_MIN_LENGTH, {
    message: `Password must be at least ${PASSWORD_MIN_LENGTH} characters long`,
  })
  @MaxLength(128)
  @Matches(PASSWORD_REGEX, { message: PASSWORD_REGEX_MESSAGE })
  newPassword: string;
}
