import {
  buildDeviceListMessage,
  buildEnrollmentMessage,
  DAK_ROTATE_CONTEXT,
  ENROLL_CONTEXT,
  LIST_CONTEXT,
  verifyDeviceListSignature,
  verifyEnrollmentSignature,
} from './device-list-signature.util';
import { verifyIdentityChangeSignature } from './identity-signature.util';
import { DEVICE_LIST_VECTOR } from './device-list-signature.vectors';

const V = DEVICE_LIST_VECTOR;

const validEnrollment = () => ({
  identityPublicKey: V.identityPublicKey,
  userId: V.userId,
  dakPub: V.dakPub,
  createdAtMs: V.createdAtMs,
  signature: V.enrollmentSig,
});

const validList = () => ({
  dakPub: V.dakPub,
  canonical: Buffer.from(V.listCanonical, 'base64'),
  signature: V.listSignature,
});

describe('verifyEnrollmentSignature (spec §3, amendment (d))', () => {
  it('accepts enrollment E produced by the real Flutter client', () => {
    expect(verifyEnrollmentSignature(validEnrollment())).toBe(true);
  });

  it('rejects the signature when a DIFFERENT DAK is claimed', () => {
    expect(
      verifyEnrollmentSignature({
        ...validEnrollment(),
        dakPub: V.lockNewIdentityPublicKey,
      }),
    ).toBe(false);
  });

  it('rejects the signature when replayed for a different account', () => {
    expect(
      verifyEnrollmentSignature({ ...validEnrollment(), userId: 4243 }),
    ).toBe(false);
  });

  it('rejects the signature when the createdAt is shifted', () => {
    expect(
      verifyEnrollmentSignature({
        ...validEnrollment(),
        createdAtMs: V.createdAtMs + 1,
      }),
    ).toBe(false);
  });

  it('rejects verification against a different identity key', () => {
    expect(
      verifyEnrollmentSignature({
        ...validEnrollment(),
        identityPublicKey: V.lockNewIdentityPublicKey,
      }),
    ).toBe(false);
  });

  it('rejects a tampered signature', () => {
    const tampered = Buffer.from(V.enrollmentSig, 'base64');
    tampered[10] ^= 0x01;
    expect(
      verifyEnrollmentSignature({
        ...validEnrollment(),
        signature: tampered.toString('base64'),
      }),
    ).toBe(false);
  });

  it.each([
    ['empty identity key', { identityPublicKey: '' }],
    ['short identity key', { identityPublicKey: 'AAAA' }],
    ['non-0x05 dakPub', { dakPub: Buffer.alloc(33, 7).toString('base64') }],
    ['zero userId', { userId: 0 }],
    ['non-integer createdAt', { createdAtMs: 1.5 }],
    ['negative createdAt', { createdAtMs: -1 }],
    ['short signature', { signature: 'AAAA' }],
  ])('fails closed on %s', (_label, override) => {
    expect(
      verifyEnrollmentSignature({ ...validEnrollment(), ...override }),
    ).toBe(false);
  });
});

describe('verifyDeviceListSignature (spec §3, amendment (d))', () => {
  it('accepts the v1 list signed by the real client DAK', () => {
    expect(verifyDeviceListSignature(validList())).toBe(true);
  });

  it('accepts the v2 list signed by the same DAK', () => {
    expect(
      verifyDeviceListSignature({
        dakPub: V.dakPub,
        canonical: Buffer.from(V.v2ListCanonical, 'base64'),
        signature: V.v2ListSignature,
      }),
    ).toBe(true);
  });

  it('rejects when a single canonical byte flips (byte-exact, fals. 23)', () => {
    const canonical = Buffer.from(V.listCanonical, 'base64');
    canonical[canonical.length - 2] ^= 0x01;
    expect(verifyDeviceListSignature({ ...validList(), canonical })).toBe(
      false,
    );
  });

  it('rejects a v1 signature presented for the v2 canonical (replay)', () => {
    expect(
      verifyDeviceListSignature({
        dakPub: V.dakPub,
        canonical: Buffer.from(V.v2ListCanonical, 'base64'),
        signature: V.listSignature,
      }),
    ).toBe(false);
  });

  it('rejects verification against a different key', () => {
    expect(
      verifyDeviceListSignature({
        ...validList(),
        dakPub: V.identityPublicKey,
      }),
    ).toBe(false);
  });

  it('does not mutate the caller-supplied canonical buffer', () => {
    const input = validList();
    const before = Buffer.from(input.canonical);
    expect(verifyDeviceListSignature(input)).toBe(true);
    expect(input.canonical.equals(before)).toBe(true);
    expect(verifyDeviceListSignature(input)).toBe(true);
  });
});

describe('cross-construction rejection (falsification 25)', () => {
  it('the enrollment signature is rejected as a list signature', () => {
    // Under the DAK it never came from…
    expect(
      verifyDeviceListSignature({ ...validList(), signature: V.enrollmentSig }),
    ).toBe(false);
    // …and under the identity key that DID mint it: the context differs.
    expect(
      verifyDeviceListSignature({
        ...validList(),
        dakPub: V.identityPublicKey,
        signature: V.enrollmentSig,
      }),
    ).toBe(false);
  });

  it('the list signature is rejected as an enrollment signature', () => {
    expect(
      verifyEnrollmentSignature({
        ...validEnrollment(),
        signature: V.listSignature,
      }),
    ).toBe(false);
  });

  it('a §6.1 registration-lock signature is rejected by BOTH new verifiers', () => {
    expect(
      verifyEnrollmentSignature({
        ...validEnrollment(),
        signature: V.lockSignature,
      }),
    ).toBe(false);
    expect(
      verifyDeviceListSignature({
        ...validList(),
        dakPub: V.identityPublicKey,
        signature: V.lockSignature,
      }),
    ).toBe(false);
  });

  it('neither new signature is accepted by the §6.1 verifier', () => {
    // The frozen §6.1 construction: sig_oldIK(newIK ‖ userId ‖ nonce). Feed
    // it the new constructions' signatures under the same identity key.
    for (const signature of [V.enrollmentSig, V.listSignature]) {
      expect(
        verifyIdentityChangeSignature({
          storedIdentityPublicKey: V.identityPublicKey,
          newIdentityPublicKey: V.lockNewIdentityPublicKey,
          userId: V.userId,
          nonce: V.lockNonce,
          signature,
        }),
      ).toBe(false);
    }
  });

  it('context prefixes are pairwise distinct, NUL-terminated, never 0x05-leading', () => {
    const contexts = [ENROLL_CONTEXT, LIST_CONTEXT, DAK_ROTATE_CONTEXT];
    for (const context of contexts) {
      expect(context.charCodeAt(0)).not.toBe(0x05);
      expect(context.endsWith('\0')).toBe(true);
    }
    expect(new Set(contexts).size).toBe(3);
    // No context is a prefix of another (unambiguous domain separation).
    expect(LIST_CONTEXT.startsWith(ENROLL_CONTEXT)).toBe(false);
    expect(DAK_ROTATE_CONTEXT.startsWith(LIST_CONTEXT)).toBe(false);
  });
});

describe('message builders', () => {
  it('builds the exact enrollment bytes: context ‖ userId ‖ dakPub ‖ createdAt', () => {
    const dakPub = Buffer.from(V.dakPub, 'base64');
    const message = buildEnrollmentMessage(V.userId, dakPub, V.createdAtMs);
    expect(message.subarray(0, 13).toString('utf8')).toBe('fp-enroll-v1\0');
    expect(message.subarray(13, 17).toString('utf8')).toBe('4242');
    expect(message.subarray(17, 50).equals(dakPub)).toBe(true);
    expect(message.subarray(50).toString('utf8')).toBe('1755600000000');
  });

  it('builds the exact list bytes: context ‖ canonical', () => {
    const canonical = Buffer.from(V.listCanonical, 'base64');
    const message = buildDeviceListMessage(canonical);
    expect(message.subarray(0, 11).toString('utf8')).toBe('fp-list-v1\0');
    expect(message.subarray(11).equals(canonical)).toBe(true);
  });
});
