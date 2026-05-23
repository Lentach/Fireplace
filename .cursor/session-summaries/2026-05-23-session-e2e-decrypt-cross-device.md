# Session: E2E cross-device decrypt fixes

**Date:** 2026-05-23

## Accomplished

- Fixed systemic E2E decrypt UX for receiver (e.g. kekw web) when sender (jarzambek) uses a different device/session than receiver's Signal store.
- `closeConversation(notify: false)` + post-frame notify in `ChatDetailScreen.dispose` (no build-phase `notifyListeners`).
- Preserve `[Decryption failed]` on history reload / cache merge; do not downgrade to `[encrypted]` on re-enter or retry pass.
- Live decrypt fail: debounced batched `_retryDecryptForPeers` instead of immediate `requestSessionRebuild` per message.
- `_updateCache` merges with existing RAM cache so pre-decrypt `[encrypted]` snapshots do not wipe failed labels.
- Tests + CLAUDE.md + graphify update.

## Key files

- `frontend/lib/providers/messaging_provider.dart`
- `frontend/lib/providers/conversations_provider.dart`
- `frontend/lib/screens/chat_detail_screen.dart`
- `frontend/test/providers/messaging_provider_race_test.dart`
- `frontend/test/providers/conversations_provider_test.dart`
- `CLAUDE.md`

## Notes for next session

- True recovery for kekw↔jarzambek still requires compatible sessions: after receiver fresh keys, sender must send **new** messages after `requestSessionRebuild` (or both re-login / clear E2E on one side). Old ciphertexts may stay undecryptable.
- Web QA: avoid comparing “fresh install” Chrome account against long-lived Android keys without expecting Bad Mac on all inbound from that peer.
