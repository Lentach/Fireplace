import { IsInt, IsNumber, IsOptional, IsPositive, Max } from 'class-validator';
import { MAX_DEVICE_ID } from '../../key-bundles/key-bundles.service';

export class FetchPreKeyBundleDto {
  @IsNumber()
  @IsPositive()
  userId: number;

  /**
   * Which device of [userId] to build a session with (Phase 1, spec §4).
   * Absent means device 1, so a client that predates devices keeps working.
   */
  @IsOptional()
  @IsInt()
  @IsPositive()
  @Max(MAX_DEVICE_ID)
  deviceId?: number;
}
