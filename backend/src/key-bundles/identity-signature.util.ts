import { verify as verifyXEdDSA } from 'curve25519-js';

/**
 * Registration lock signature verification (Phase 0b, multi-device spec §6.1).
 *
 * A key-bundle upload that REPLACES the stored identity key must carry proof
 * that the holder of the PREVIOUS identity key authorized the replacement:
 *
 *   signature = sig_oldIK( newIdentityPublicKey ‖ userId ‖ serverNonce )
 *
 * Byte layout, fixed and verified against a real client-produced vector:
 *   - newIdentityPublicKey: 33 bytes, the client's serialization INCLUDING the
 *     leading 0x05 Curve25519 type byte (base64 on the wire).
 *   - userId: its decimal representation as UTF-8 (binds the proof to one
 *     account, so a signature cannot be replayed onto another).
 *   - serverNonce: 32 CSPRNG bytes issued to the caller's socket session
 *     (binds the proof to one live session and makes it single-use).
 *
 * The signing side is the Signal XEdDSA construction (`Curve.calculateSignature`
 * in libsignal_protocol_dart): an Ed25519-form signature over a Curve25519
 * identity key, carrying the Edwards x-sign bit in the top bit of the last
 * signature byte. `curve25519-js.verify` implements the matching convention and
 * expects the 32-byte Montgomery key WITHOUT the type byte.
 *
 * Fails CLOSED: any malformed input, wrong length, or thrown error is a
 * rejection, never an acceptance.
 */
export const IDENTITY_KEY_SERIALIZED_LENGTH = 33;
export const IDENTITY_SIGNATURE_LENGTH = 64;
export const REGISTRATION_LOCK_NONCE_LENGTH = 32;

/** Curve25519 public keys are serialized with this leading type byte. */
const DJB_TYPE_BYTE = 0x05;

export interface IdentityChangeProofInput {
  /** base64, 33 bytes — the identity key currently stored for the account. */
  storedIdentityPublicKey: string;
  /** base64, 33 bytes — the identity key the upload wants to install. */
  newIdentityPublicKey: string;
  userId: number;
  /** base64, 32 bytes — the nonce this socket session was issued. */
  nonce: string;
  /** base64, 64 bytes — XEdDSA signature by the stored identity key. */
  signature: string;
}

function decodeExact(value: string, expectedLength: number): Buffer | null {
  if (typeof value !== 'string' || value.length === 0) return null;
  let decoded: Buffer;
  try {
    decoded = Buffer.from(value, 'base64');
  } catch {
    return null;
  }
  // Buffer.from silently ignores invalid base64, so the length check is the
  // real validation. Re-encoding would also catch non-canonical input, but the
  // length + signature check already make a forgery attempt useless.
  if (decoded.length !== expectedLength) return null;
  return decoded;
}

/**
 * Builds the exact byte string the client signed. Exported for tests and for
 * any future signer on the server side (§6.3 primary rotation).
 */
export function buildIdentityChangeMessage(
  newIdentityPublicKey: Buffer,
  userId: number,
  nonce: Buffer,
): Buffer {
  return Buffer.concat([
    newIdentityPublicKey,
    Buffer.from(String(userId), 'utf8'),
    nonce,
  ]);
}

export function verifyIdentityChangeSignature(
  input: IdentityChangeProofInput,
): boolean {
  const storedKey = decodeExact(
    input.storedIdentityPublicKey,
    IDENTITY_KEY_SERIALIZED_LENGTH,
  );
  const newKey = decodeExact(
    input.newIdentityPublicKey,
    IDENTITY_KEY_SERIALIZED_LENGTH,
  );
  const nonce = decodeExact(input.nonce, REGISTRATION_LOCK_NONCE_LENGTH);
  const signature = decodeExact(input.signature, IDENTITY_SIGNATURE_LENGTH);
  if (!storedKey || !newKey || !nonce || !signature) return false;
  if (storedKey[0] !== DJB_TYPE_BYTE || newKey[0] !== DJB_TYPE_BYTE) {
    return false;
  }
  if (!Number.isInteger(input.userId) || input.userId <= 0) return false;

  const message = buildIdentityChangeMessage(newKey, input.userId, nonce);

  // The verifier strips the sign bit from the key and the signature IN PLACE.
  // Fresh Uint8Arrays keep that mutation off any caller-owned buffer.
  const verifyKey = Uint8Array.from(storedKey.subarray(1));
  const verifyMessage = Uint8Array.from(message);
  const verifySignature = Uint8Array.from(signature);

  try {
    return verifyXEdDSA(verifyKey, verifyMessage, verifySignature) === true;
  } catch {
    return false;
  }
}
