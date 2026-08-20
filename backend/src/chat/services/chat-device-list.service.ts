import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import {
  DeviceListRejectedError,
  DeviceListService,
} from '../../key-bundles/device-list.service';
import {
  EnrollDeviceAuthorityDto,
  GetDeviceListDto,
  UpdateDeviceListDto,
} from '../dto/device-list.dto';
import { validateDto } from '../utils/dto.validator';
import { userRoom } from '../utils/user-room';

/**
 * socket.io declares `Socket.data` as `any`; one documented narrowing keeps
 * that assertion in a single place (same pattern as chat-key-exchange).
 */
function socketUserId(client: Socket): number | undefined {
  return (client.data as { user?: { id: number } }).user?.id;
}
/**
 * Wire surface of the DAK-signed device list (Phase 2 T2, spec §7 row 424:
 * `getDeviceList` / `deviceListChanged`; the enrollment event is T2's — §7
 * names no enrollment event because enrollment rides the enable-linking
 * action that precedes provisioning, spec §3 "created on the primary when
 * multi-device is first enabled").
 *
 * Contract style: request-event → response-event, refusals as
 * `success:false` answers with stable codes — a deliberate refusal is an
 * answer, not a server `error`. Every accepted list WRITE broadcasts
 * `deviceListChanged { userId, listVersion }` to the account's sessions
 * (§5.3: the user room carries list changes; peers re-fetch via
 * `getDeviceList`).
 */
@Injectable()
export class ChatDeviceListService {
  private readonly logger = new Logger(ChatDeviceListService.name);

  constructor(private readonly deviceListService: DeviceListService) {}

  async handleEnrollDeviceAuthority(
    client: Socket,
    data: unknown,
    server: Server,
  ): Promise<void> {
    const userId = socketUserId(client);
    if (!userId) return;
    try {
      const dto = validateDto(EnrollDeviceAuthorityDto, data);
      await this.deviceListService.enroll(userId, {
        dakPub: dto.dakPub,
        enrollmentSig: dto.enrollmentSig,
        createdAt: dto.createdAt,
        listCanonical: dto.listCanonical,
        listSignature: dto.listSignature,
      });
      client.emit('deviceAuthorityEnrolled', { success: true, listVersion: 1 });
      server
        .to(userRoom(userId))
        .emit('deviceListChanged', { userId, listVersion: 1 });
    } catch (error) {
      if (error instanceof DeviceListRejectedError) {
        // The gate did its job; the client reads the code, never retries
        // blindly. Nothing was written.
        client.emit('deviceAuthorityEnrolled', {
          success: false,
          error: error.code,
        });
        return;
      }
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(
        `enrollDeviceAuthority failed userId=${userId}: ${message}`,
      );
      client.emit('deviceAuthorityEnrolled', {
        success: false,
        error: 'enrollment_failed',
      });
    }
  }

  async handleUpdateDeviceList(
    client: Socket,
    data: unknown,
    server: Server,
  ): Promise<void> {
    const userId = socketUserId(client);
    if (!userId) return;
    try {
      const dto = validateDto(UpdateDeviceListDto, data);
      const listVersion = await this.deviceListService.applySignedListUpdate(
        userId,
        {
          listCanonical: dto.listCanonical,
          listSignature: dto.listSignature,
        },
      );
      client.emit('deviceListUpdated', { success: true, listVersion });
      server
        .to(userRoom(userId))
        .emit('deviceListChanged', { userId, listVersion });
    } catch (error) {
      if (error instanceof DeviceListRejectedError) {
        client.emit('deviceListUpdated', {
          success: false,
          error: error.code,
        });
        return;
      }
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(`updateDeviceList failed userId=${userId}: ${message}`);
      client.emit('deviceListUpdated', {
        success: false,
        error: 'update_failed',
      });
    }
  }

  /**
   * Serves the stored enrollment + list for ANY requested user: peers run the
   * I7 chain themselves and need the full record. `listCanonical` is echoed
   * as the STORED base64 string verbatim (falsification 23);
   * `enrollmentCreatedAt` as the signed integer milliseconds, so E re-verifies
   * bit-for-bit.
   */
  async handleGetDeviceList(client: Socket, data: unknown): Promise<void> {
    const requesterId = socketUserId(client);
    if (!requesterId) return;
    try {
      const dto = validateDto(GetDeviceListDto, data);
      const row = await this.deviceListService.getAuthorization(dto.userId);
      client.emit('deviceList', {
        userId: dto.userId,
        authorization: row
          ? {
              dakPub: row.dakPub,
              enrollmentSig: row.enrollmentSig,
              enrollmentCreatedAt: row.enrollmentCreatedAt.getTime(),
              listVersion: row.listVersion,
              listSignature: row.listSignature,
              listCanonical: row.listCanonical,
            }
          : null,
      });
    } catch (error) {
      // Silence is fail-closed on the client (I5: an unanswered fetch means
      // "cannot verify", never "no devices").
      const message = error instanceof Error ? error.message : String(error);
      this.logger.error(
        `getDeviceList failed requesterId=${requesterId}: ${message}`,
      );
    }
  }
}
