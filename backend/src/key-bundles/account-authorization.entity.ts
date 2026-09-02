import {
  Column,
  Entity,
  JoinColumn,
  OneToOne,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

/**
 * The account's multi-device enrollment (Phase 2 T1, spec §3/§4 + §12 Stage-0
 * amendment (g)).
 *
 * ONE row per account, created lazily when multi-device is first enabled and
 * pinned FIRST-WRITE-WINS: it carries the DAK public key, the IK-signed
 * enrollment record E, and the current DAK-signed device list. Peers verify
 * *their TOFU'd IK → E → DAK → list*, so the server stores but can never
 * mint any of it (invariant I1). No backfill exists by design — a
 * single-device account has no enrollment.
 *
 * `enrollmentCreatedAt` is stored beyond §4's column list because the signed
 * bytes of E are `"fp-enroll-v1\0" ‖ userId ‖ dakPub ‖ createdAt` (§3 +
 * amendment (d)) — without the createdAt that went under the signature, E is
 * unverifiable.
 *
 * `listCanonical` is OPAQUE BASE64 BYTES (§3 transport rule): hash and
 * signature are computed over the decoded bytes verbatim; nothing may ever
 * parse and re-serialize it.
 *
 * Prod truth is migration 0016.
 */
@Entity('account_authorizations')
export class AccountAuthorization {
  @PrimaryColumn()
  userId: number;

  // FK with CASCADE (migration 0016): account deletion destroys the
  // enrollment. Scalar userId stays the API.
  @OneToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  /** Device-authorization public key (base64). Custody: primary only (§3). */
  @Column('text')
  dakPub: string;

  /** sig_IK("fp-enroll-v1\0" ‖ userId ‖ dakPub ‖ createdAt) (base64). */
  @Column('text')
  enrollmentSig: string;

  /** The createdAt the enrollment signature covers. */
  @Column({ type: 'timestamp' })
  enrollmentCreatedAt: Date;

  /** Monotonic list version — never restarts, even across a §6.2 reset. */
  @Column()
  listVersion: number;

  /** sig_DAK("fp-list-v1\0" ‖ listCanonical) (base64). */
  @Column('text')
  listSignature: string;

  /** Canonical device-list bytes as opaque base64 (§3 transport rule). */
  @Column('text')
  listCanonical: string;

  @UpdateDateColumn()
  updatedAt: Date;
}
