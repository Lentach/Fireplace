import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from './device.entity';
import { DEFAULT_DEVICE_ID } from './key-bundles.service';

/**
 * The account's devices (Phase 1, multi-device spec §4).
 *
 * Phase 1 does not GRANT a second device — provisioning is Phase 2. What it
 * does is make the one device every account already has representable, and
 * keep the row alive as sessions connect, so revocation and the device list
 * have something real to act on rather than a table only a backfill ever
 * touched.
 */
@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
  ) {}

  /**
   * Records that a device of this account is connected, creating its row on
   * first sight.
   *
   * Device 1 is the account's primary until provisioning ships (invariant I2:
   * only a Keystore-capable device may be primary, and today there is exactly
   * one device). Called on every connect, so it must be cheap and must never
   * break the connection: a failure here costs a `lastSeenAt`, not a session.
   */
  async touch(
    userId: number,
    deviceId: number = DEFAULT_DEVICE_ID,
    platform?: string,
  ): Promise<void> {
    try {
      await this.deviceRepo.upsert(
        {
          userId,
          deviceId,
          isPrimary: deviceId === DEFAULT_DEVICE_ID,
          platform: platform ?? null,
          lastSeenAt: new Date(),
        },
        { conflictPaths: ['userId', 'deviceId'] },
      );
    } catch (error) {
      this.logger.warn(
        `[devices] touch failed userId=${userId} deviceId=${deviceId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  /** Every device of an account, oldest first. Revoked rows included. */
  async listForUser(userId: number): Promise<Device[]> {
    return this.deviceRepo.find({
      where: { userId },
      order: { deviceId: 'ASC' },
    });
  }
}
