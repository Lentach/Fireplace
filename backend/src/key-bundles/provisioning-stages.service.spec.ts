import {
  PROVISIONING_STAGE_TTL_MS,
  ProvisioningStagesService,
} from './provisioning-stages.service';

/**
 * The in-memory §5.1 provisioning stage store (Phase 2 T3, spec §12
 * amendments (a)/(iv)). The laws that matter: TTL is real (expired =
 * unknown), the deviceId is memoized once, `consume` is a one-shot CAS so
 * two concurrent completes admit exactly one, `restore` re-arms a failed
 * commit, and `retire` ends blob availability forever (falsification 18's
 * boundary: re-fetchable UNTIL commit, never after).
 */
describe('ProvisioningStagesService', () => {
  let service: ProvisioningStagesService;

  beforeEach(() => {
    jest.useFakeTimers();
    service = new ProvisioningStagesService();
  });

  afterEach(() => {
    service.onModuleDestroy();
    jest.useRealTimers();
  });

  it('opens a stage with a memoized deviceId and a 10-minute TTL', () => {
    const stage = service.open(7, 'socket-1', 2);

    expect(stage.deviceId).toBe(2);
    expect(stage.openerSocketId).toBe('socket-1');
    expect(stage.expiresAt).toBe(Date.now() + PROVISIONING_STAGE_TTL_MS);
    // The memoized id never changes across accesses (amendment (a)).
    expect(service.get(stage.provisioningId)?.deviceId).toBe(2);
    expect(service.get(stage.provisioningId)?.deviceId).toBe(2);
  });

  it('an expired stage is unknown on access (lazy expiry)', () => {
    const stage = service.open(7, 'socket-1', 2);

    jest.advanceTimersByTime(PROVISIONING_STAGE_TTL_MS - 1);
    expect(service.get(stage.provisioningId)).not.toBeNull();

    jest.advanceTimersByTime(1);
    expect(service.get(stage.provisioningId)).toBeNull();
  });

  it('the periodic sweep clears expired stages without access', () => {
    const stage = service.open(7, 'socket-1', 2);

    // Past TTL, the next sweep tick runs and the map forgets the stage —
    // proven via the public surface after the timer fires.
    jest.advanceTimersByTime(PROVISIONING_STAGE_TTL_MS + 60 * 1000);
    expect(service.get(stage.provisioningId)).toBeNull();
  });

  it('consume is a one-shot CAS: of two immediate consumes one wins', () => {
    const stage = service.open(7, 'socket-1', 2);

    // Synchronous back-to-back, exactly how two racing completes interleave
    // on the event loop (amendment (a)).
    const first = service.consume(stage.provisioningId);
    const second = service.consume(stage.provisioningId);

    expect(first).toBe(true);
    expect(second).toBe(false);
  });

  it('restore re-arms a consumed stage for the stale_version retry', () => {
    const stage = service.open(7, 'socket-1', 2);
    stage.blob = 'blob';

    expect(service.consume(stage.provisioningId)).toBe(true);
    service.restore(stage.provisioningId);

    // Falsification 20: the primary re-signs v+2 against the SAME stage and
    // the retried complete consumes it again; the blob survived the failure.
    expect(service.get(stage.provisioningId)?.consumed).toBe(false);
    expect(service.get(stage.provisioningId)?.blob).toBe('blob');
    expect(service.consume(stage.provisioningId)).toBe(true);
  });

  it('retire keeps the stage consumed and destroys the blob', () => {
    const stage = service.open(7, 'socket-1', 2);
    stage.blob = 'blob';
    stage.stagedListCanonical = 'canonical';
    stage.stagedListSignature = 'signature';
    expect(service.consume(stage.provisioningId)).toBe(true);

    service.retire(stage.provisioningId);

    // Amendment (a): no blob refetch after commit; a duplicate complete
    // still finds the stage (until TTL) and reads `consumed`.
    const retired = service.get(stage.provisioningId);
    expect(retired?.consumed).toBe(true);
    expect(retired?.blob).toBeNull();
    expect(retired?.stagedListCanonical).toBeNull();
    expect(retired?.stagedListSignature).toBeNull();
    expect(service.consume(stage.provisioningId)).toBe(false);
  });

  it('discard forgets the stage entirely', () => {
    const stage = service.open(7, 'socket-1', 2);

    service.discard(stage.provisioningId);

    expect(service.get(stage.provisioningId)).toBeNull();
  });

  it('multiple concurrent stages per account coexist independently', () => {
    // Falsification 20 depends on two ceremonies racing the same account.
    const a = service.open(7, 'socket-1', 2);
    const b = service.open(7, 'socket-2', 3);

    expect(a.provisioningId).not.toBe(b.provisioningId);
    expect(service.consume(a.provisioningId)).toBe(true);
    // Consuming one stage never touches its sibling.
    expect(service.get(b.provisioningId)?.consumed).toBe(false);
    expect(service.consume(b.provisioningId)).toBe(true);
  });
});
