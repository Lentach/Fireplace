import {
  IsInt,
  IsNotEmpty,
  IsPositive,
  IsString,
  MaxLength,
} from 'class-validator';

/**
 * DAK enrollment + signed device list (Phase 2 T2, spec §3/§7 row 424).
 *
 * Length caps are transport sanity only — the real validation is the
 * signature/parse gauntlet in DeviceListService. `listCanonical` is opaque
 * base64 whose decoded form is bounded by the canonical grammar itself
 * (≤64 entries); 16 KiB leaves ample headroom without accepting megabytes.
 */

export class EnrollDeviceAuthorityDto {
  /** base64, 33 bytes — DAK public key. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  dakPub: string;

  /** base64, 64 bytes — sig_IK("fp-enroll-v1\0" ‖ …). */
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  enrollmentSig: string;

  /** Integer milliseconds since epoch, exactly as signed. */
  @IsInt()
  @IsPositive()
  createdAt: number;

  /** Opaque base64 canonical bytes of the v1 list. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(16384)
  listCanonical: string;

  /** base64, 64 bytes — sig_DAK("fp-list-v1\0" ‖ listCanonical). */
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  listSignature: string;
}

export class UpdateDeviceListDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(16384)
  listCanonical: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  listSignature: string;
}

export class GetDeviceListDto {
  /** Whose enrollment + signed list to serve — any user (peers verify I7). */
  @IsInt()
  @IsPositive()
  userId: number;
}
