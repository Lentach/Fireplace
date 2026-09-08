import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';

/**
 * Provisioning ceremony wire payloads (Phase 2 T3, spec §5.1 + §12
 * amendments (a)-(c), (i)-(iv)).
 *
 * Length caps are transport sanity only — the real gate is the stage lookup
 * (opener binding, TTL, pinned ephemeral) plus the signature/parse gauntlet
 * in ChatProvisioningService. `openProvisioning` carries only the opener's
 * ROLE (amendment (lxxvii)), defaulting to 'new' for byte-compatibility.
 *
 * `ephPubN` deliberately appears in NO payload (amendment (c)): it travels
 * out-of-band only, on the QR/manual code.
 */

export class OpenProvisioningDto {
  /** Which side of the ceremony the opener plays; omitted means 'new'. */
  @IsOptional()
  @IsIn(['new', 'primary'])
  role?: 'new' | 'primary';
}

export class ProvisioningHelloDto {
  /** UUID minted by the server at openProvisioning. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  provisioningId: string;

  /** base64, 33 bytes — the primary's ephemeral public key. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  ephPubP: string;

  /**
   * Informational platform label of the HELLO side (amendment (lxxx) clause
   * 3). Only reason it exists: when the PRIMARY opened the ceremony
   * (amendment (lxxvii)) this is the only channel by which the joining
   * device's label reaches the signer, so without it every such link lands
   * in the roster as 'unknown'. OPTIONAL — an older client omits it and is
   * unchanged. Same `^[A-Za-z0-9_-]{1,32}$` bound the OOB code enforces; it
   * is metadata, never a crypto input.
   */
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9_-]{1,32}$/)
  platform?: string;
}

export class ProvisionDeviceDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  provisioningId: string;

  /** Opaque base64 — the SAS-secret-encrypted IK-bearing blob (§5.1). */
  @IsString()
  @IsNotEmpty()
  @MaxLength(16384)
  blob: string;

  /** Opaque base64 canonical bytes of the staged v+1 list. */
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

export class FetchProvisioningBlobDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  provisioningId: string;
}

export class ProvisioningCompleteDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  provisioningId: string;
}

export class CancelProvisioningDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  provisioningId: string;
}
