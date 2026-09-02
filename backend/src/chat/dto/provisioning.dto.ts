import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

/**
 * Provisioning ceremony wire payloads (Phase 2 T3, spec §5.1 + §12
 * amendments (a)-(c), (i)-(iv)).
 *
 * Length caps are transport sanity only — the real gate is the stage lookup
 * (opener binding, TTL, pinned ephemeral) plus the signature/parse gauntlet
 * in ChatProvisioningService. `openProvisioning` carries no payload and
 * therefore has no DTO.
 *
 * `ephPubN` deliberately appears in NO payload (amendment (c)): it travels
 * out-of-band only, on the QR/manual code.
 */

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
