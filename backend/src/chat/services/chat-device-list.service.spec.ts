import { Test, TestingModule } from '@nestjs/testing';
import { Socket } from 'socket.io';
import { ChatDeviceListService } from './chat-device-list.service';
import { ChatValidationService } from './chat-validation.service';
import { DeviceListService } from '../../key-bundles/device-list.service';
import { ConversationsService } from '../../conversations/conversations.service';

/**
 * WHO MAY READ AN ACCOUNT'S DEVICE ROSTER (spec §12 amendment (xliii)).
 *
 * `getDeviceList` used the requester id only to check that SOMEONE was
 * authenticated, then served whatever `userId` the payload named. That made it
 * a device-count, platform and timeline oracle over every account on the
 * instance: walk the ids and learn how many devices each user runs, on which
 * platforms, when each was added and when any was revoked — precise profiling
 * in an app whose whole premise is metadata minimisation, on a repository
 * public since 2026-08-18.
 *
 * These tests pin the three ways in and, just as importantly, the way OUT: a
 * refusal must stay SILENT, because answering at all would confirm whether an
 * account exists.
 */
describe('ChatDeviceListService.handleGetDeviceList entitlement', () => {
  const REQUESTER = 7;
  const TARGET = 9;

  let service: ChatDeviceListService;
  let getAuthorization: jest.Mock;
  let validateCanMessage: jest.Mock;
  let findByUsers: jest.Mock;
  let emit: jest.Mock;
  let client: Partial<Socket>;

  /** The stored row the handler projects when the caller is entitled. */
  const authorizationRow = {
    dakPub: 'dak',
    enrollmentSig: 'sig',
    enrollmentCreatedAt: new Date(1_700_000_000_000),
    listVersion: 3,
    listSignature: 'list-sig',
    listCanonical: 'canonical-bytes',
  };

  /** The same row as it appears ON THE WIRE: the date becomes signed ms. */
  const authorizationProjection = {
    ...authorizationRow,
    enrollmentCreatedAt: authorizationRow.enrollmentCreatedAt.getTime(),
  };

  beforeEach(async () => {
    getAuthorization = jest.fn().mockResolvedValue(authorizationRow);
    // Refuses by default, so every test states its OWN reason for being let in
    // and nothing passes merely because the harness was permissive.
    validateCanMessage = jest.fn().mockResolvedValue({
      valid: false,
      error: 'You can only message friends',
    });
    findByUsers = jest.fn().mockResolvedValue(null);
    emit = jest.fn();
    client = { data: { user: { id: REQUESTER } }, emit };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatDeviceListService,
        { provide: DeviceListService, useValue: { getAuthorization } },
        { provide: ChatValidationService, useValue: { validateCanMessage } },
        { provide: ConversationsService, useValue: { findByUsers } },
      ],
    }).compile();
    service = module.get(ChatDeviceListService);
  });

  const get = (userId: number) =>
    service.handleGetDeviceList(client as Socket, { userId });

  it('serves YOUR OWN roster, always', async () => {
    await get(REQUESTER);

    // Discloses nothing the caller does not already hold, and the I7 own-skew
    // re-fetch depends on it.
    expect(emit).toHaveBeenCalledWith(
      'deviceList',
      expect.objectContaining({ userId: REQUESTER }),
    );
    expect(validateCanMessage).not.toHaveBeenCalled();
  });

  it('serves a peer you may message', async () => {
    validateCanMessage.mockResolvedValue({ valid: true });

    await get(TARGET);

    expect(validateCanMessage).toHaveBeenCalledWith(REQUESTER, TARGET);
    expect(emit).toHaveBeenCalledWith(
      'deviceList',
      expect.objectContaining({
        userId: TARGET,
        authorization: authorizationProjection,
      }),
    );
    // The carve-out is not consulted when the cheap predicate already passed.
    expect(findByUsers).not.toHaveBeenCalled();
  });

  it('REFUSES a stranger, in silence', async () => {
    await get(TARGET);

    // Silence is fail-closed on the client (I5: an unanswered fetch means
    // "cannot verify", never "no devices"), and answering would itself
    // confirm whether the account exists.
    expect(emit).not.toHaveBeenCalled();
    expect(getAuthorization).not.toHaveBeenCalled();
  });

  it('still serves a peer you share a CONVERSATION with, after a block', async () => {
    // The carve-out, and it is required rather than convenient: the accept-side
    // gate needs this list to decrypt, so without it a peer who unfriends or
    // blocks you makes history you ALREADY RECEIVED permanently unreadable.
    validateCanMessage.mockResolvedValue({ valid: false, error: 'blocked' });
    findByUsers.mockResolvedValue({ id: 42 });

    await get(TARGET);

    expect(findByUsers).toHaveBeenCalledWith(REQUESTER, TARGET);
    expect(emit).toHaveBeenCalledWith(
      'deviceList',
      expect.objectContaining({ userId: TARGET }),
    );
  });

  it('refuses an unauthenticated socket without touching the database', async () => {
    client = { data: {}, emit };

    await get(TARGET);

    expect(emit).not.toHaveBeenCalled();
    expect(validateCanMessage).not.toHaveBeenCalled();
    expect(getAuthorization).not.toHaveBeenCalled();
  });

  it('echoes the stored listCanonical verbatim for an entitled caller', async () => {
    // Falsification 23: the bytes are re-verified bit-for-bit by the peer, so
    // the gate must not have changed what an ENTITLED caller receives.
    validateCanMessage.mockResolvedValue({ valid: true });

    await get(TARGET);

    expect(emit).toHaveBeenCalledWith('deviceList', {
      userId: TARGET,
      authorization: {
        dakPub: 'dak',
        enrollmentSig: 'sig',
        enrollmentCreatedAt: 1_700_000_000_000,
        listVersion: 3,
        listSignature: 'list-sig',
        listCanonical: 'canonical-bytes',
      },
    });
  });
});
