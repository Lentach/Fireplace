# Storage-durability instrumentation — name the layer (code vs storage vs establishment)

**Date:** 2026-06-13

## What was done

Stopped the fix-on-fix loop (10 rounds in). Decision: NO more behavioural fixes until evidence names the failing layer. Added **observe-only** instrumentation to close the one axis the existing diag log is blind to — **storage durability** — so the planned "fresh conversation on two 0.0.55 devices, reload once" diagnostic becomes conclusive instead of suggestive.

Context established this session (analysis, not code):
- The 0.0.53 fixes ARE deployed and working (logs show `tempId` in SEND events, single `SESSION_RESET` per peer, no `SESSION_DELETE`/`SESSION_DELETED_FOR_REBUILD`, `needsRebuild:false` on inbound-triggered sends).
- Remaining failures are **session ABSENCE** (`ctype:2, hasSession:false` — peer has a session, receiver has none), a different failure mode than the session DESTRUCTION every prior fix targeted.
- Existing logs already RULE OUT OTP depletion (would throw `InvalidKeyIdException`; never seen — only `NoSession`/`Bad Mac`).
- Existing logs CANNOT distinguish "storage lost the session" from "never established" — nothing observes the storage layer. That's the gap this instrumentation closes.
- Identity surviving (`needsKeyUpload:false`) actually argues AGAINST wholesale localStorage eviction for the captured failures (eviction is all-or-nothing per origin) — so storage is a real long-term liability but maybe not the active cause. The probes will settle it.

## Instrumentation (all TEMP, removal documented in CLAUDE.md §1)
- `SESSION_INVENTORY {count, peerIds}` — at every E2E init; **the primary signal**: peer present one start, gone the next, with no matching delete ⇒ storage eviction.
- `SESSION_STORE_DELETE {peerId}` — every store-level delete (ours or libsignal's), so an inventory drop is attributable to code-vs-storage.
- `SESSION_STORE_WRITE_FAIL {peerId, err}` — thrown session write (quota/private mode). Designed around the SharedPreferences in-memory-cache caveat: an immediate read-back can't prove durability (it serves the cached value even when the localStorage flush dropped), so the cross-reload inventory is the real test, not read-back.
- `STORAGE_PERSIST {supported, granted}` — once per run; `utils/storage_persist.dart` stub/web pair calling `navigator.storage.persist()`. Doubles as the one safe storage hardening (eviction exemption on installed PWAs). App never called it before (grep-confirmed).

## Key files
- NEW `frontend/lib/utils/storage_persist{,_stub,_web}.dart` (facade `if (dart.library.html)` → `package:web` StorageManager)
- `frontend/lib/services/encryption/signal_stores.dart` (storeSession try/rethrow + WRITE_FAIL, deleteSession log, `inventoryPeerIds`)
- `frontend/lib/services/encryption_service.dart` (`sessionInventoryPeerIds` passthrough)
- `frontend/lib/providers/encryption_provider.dart` (`_logSessionInventory`, `_probeStoragePersistenceOnce`, wired in `initializeE2E`)
- `frontend/test/services/encryption_service_content_cache_test.dart` (+1 parse test)
- `CLAUDE.md` §1 (TEMP-probes bullet + revert list), `frontend/pubspec.yaml` 0.0.55

## Verification
- `flutter analyze` on all changed/new files → No issues.
- New `sessionInventoryPeerIds` test (multi-digit peer ids parse; non-session keys excluded) passes; targeted E2E suites 42 green.
- Full frontend suite **372 green**.

## Notes for next session — the diagnostic protocol
Deploy 0.0.55 (flutter clean, gitCommit check, PWA cache-bust). Then capture, on BOTH devices, aligned by msgId:
1. Fresh conversation, peer never messaged before; peer sends 3 messages.
2. Read first `DECRYPT_START` for that peer: `ctype:3`+decrypts ⇒ establishment OK (remaining failures = old corpses aging out); `ctype:2 hasSession:false` or failing `ctype:3` ⇒ asymmetry live (establishment/glare).
3. Note `SESSION_INVENTORY` at startup; **reload the app**; note it again. Peer dropped with no `SESSION_STORE_DELETE` between ⇒ **storage**. Stable inventory but messages still fail ⇒ **code/establishment**.
4. `STORAGE_PERSIST {granted:false}` on the affected device ⇒ eviction is possible there (and the persist() call now requests exemption).
The capture NAMES the layer → then (and only then) commit to the direction: surgical "delete reactive resets + proactive inbound heal" (code/establishment) vs storage hardening (storage). Do NOT write another behavioural fix before this.
