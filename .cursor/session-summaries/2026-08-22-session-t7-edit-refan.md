# 2026-08-22 — T7: edit re-fan under envelopes (§5.7)

**Status: BUILT, REVIEWED TWICE (no P0/P1 either time), WIRE-PROVEN, APP-PROVEN. Pushed. NOT merged,
NOT deployed.** Branch `feat/takeover-alarm-0a` in worktree `C:/Users/Lentach/Desktop/fireplace-0a`.

Closure + deviations + what is owed: decision record §12. Normative settlement: spec §12 **(xxx)–(xxxiv)**.

## What was actually wrong

Editing a message re-encrypted it for the peer's **device 1 only** — and wrote the ciphertext to the
**legacy `messages.encryptedContent` column**, which a multi-device row deliberately keeps NULL because
every device reads its own row in `message_envelopes`. So the edited text lived **only in the live
socket emit**: every device, the peer's device 1 included, re-read the ORIGINAL ciphertext after a
reload. T7 is therefore a migration of edits onto the envelope table, not merely a wider fan-out.

## The settlement, ratified before any code (`4a57f74`)

Five open questions, all answered as recommended. Four filled gaps; **(xxx) fixed a latent bug in the
frozen spec**, found by reading the receive path rather than the text:

- **(xxx)** An edit UPDATES `messages.originDeviceId` to the **EDITING** device. Receivers key their
  Signal session off that field (`messaging_provider.decrypt.dart:1354-1355`, `:1372`) and the
  accept-side gate keys on it too, so §5.7's "any of the sender's devices may edit" would otherwise
  Bad-MAC every copy of a row that decrypted fine before the edit. The field now means *the device that
  produced the ciphertext currently stored*; every envelope of one row always has exactly one producer,
  so no second device-id column is needed. Rejected: a separate `editorDeviceId` (two fields that can
  disagree) and forbidding non-origin edits (contradicts §5.7 and would remove the edit action on a
  second device).
- **(xxxi)** The staleness bounce reuses the EXISTING `deviceListStale` event; `editMessage` gains
  `senderListVersion`/`recipientListVersion`; `editMessageFailed` keeps its four codes and inherits the
  (v) envelope-shape codes.
- **(xxxii)** The legacy column is written for LEGACY rows ONLY — `content === '[encrypted]' &&
  encryptedContent == null` IS the server's new-model discriminator (`ackEnvelopeStatus`), so writing it
  on a new-model row silently reclassifies that row after a single edit.
- **(xxxiii)** Envelopes of devices dropped between send and edit are LEFT: (g) names the message-delete
  CASCADE as the only destruction path, and a revoked device is already unreachable.
- **(xxxiv)** An edited envelope carries `senderListInfo` — otherwise it is the one ciphertext-bearing
  message with no layer-2 cross-check.

## Spine

`4a57f74` settlement → `f3baaf7` backend → `3c9e16e` client → `3077d06` wire falsification 24 →
`febbbae` stale-refusal divergence fix + docs → `eaf1e78` review fold → `7c297c2` second fold →
`39816f1` closure docs.

## Three findings that reshaped the work

1. **A new refusal is only half a feature.** T7 gave the edit path a `deviceListStale` answer that no
   client code handled: `onDeviceListStale` correlates by `tempId` and returned early, while an edit
   refusal carries `messageId`. The optimistic edit would have sat on the editing device forever while
   the server and peer kept the old text, surviving a reopen. Fixed in `febbbae` with a bounded
   `_retryStaleEdit` that repairs, then reverts on exhaustion. **For every refusal you add, name the
   client code that drives it to a conclusion.**
2. **⚠️ THE TEST THAT COULD NOT FAIL, again — caught by the fold reviewer, not by me.** The test
   guarding the retry-budget reset bounced the row FOUR times; the fourth trips the exhaustion path
   whose first statement already clears the counter, so the second edit started fresh with or without
   the fix. Three bounces leave it at 3. Then PROVEN: with the production line removed the suite is
   1518 passing + 1 FAILING; restored, 1519 pass. Do this proof for any test whose value is a guard.
3. **The harness had a hidden per-user budget and we were sitting exactly on it.**
   `provisioningComplete` is throttled **10 per 15 min keyed by USER**, and every ceremony client does
   `adoptAccountFrom(alice)`. The suite already spent all 10, so an 11th ceremony gets **no answer at
   all** — the guard THROWS instead of emitting. Symptom: whichever test held the 11th call failed, so
   moving our test moved the failure. Falsifications 6 and 24 now share ONE linked device via a
   memoized `secondDeviceOfAlice()` fixture. **T8 has zero headroom here.**

## Review

- **Ticket reviewer: SHIP-WITH-FIXES, 0 P0, 0 P1.** Confirmed the UPSERT conflict clause, the
  transaction, (xxx) end to end, guard ordering and the (xxxii) discriminator. Four findings folded: the
  per-messageId retry budget accumulating across edits (P2); falsification 24 overclaiming (P2); a
  delete-vs-edit race throwing with nothing emitted (P3); leaked `_pendingEdits` snapshots (P3).
- **Fold reviewer: correct, 0 P0, 0 P1** — plus the vacuous-test catch above and a P3 on log level (a
  raced delete is now `warn`, any other throw `error`, so a systemic DB fault cannot hide as "users
  editing deleted messages").

## Proof

Wire falsification 24 passes. **App-proof on 193 → 297, message 1012:** sent and DELIVERED
(`deliveredAt 04:41:15.544`, `createdAt 04:41:15.511`), edited from the real UI at 04:42:25
(`[edit] User 193 edited message 1012 deviceId=1 envelopes=1`). Afterwards: `editedAt` set, legacy
column still NULL, `deliveryStatus` still READ, and the envelope's `deliveredAt`/`createdAt`
**byte-identical to their pre-edit values** — F8 observed on a real row, not asserted through a mock.
The peer rendered "T7 AFTER refan" with the *edytowano* marker and **still showed it after a full
reload**, which before T7 would have resurrected the pre-edit text. Server-side envelope replacement is
proven separately by the wire run (message **1011**: `originDeviceId 7`, the EDITING device rather than
the device 1 that sent it; bob's envelope holds the edited bytes with `deliveredAt` still set; alice's
device 1, which had no envelope because it was the origin, has an INSERTED one).

## Owed

- The wire suite has no read path for envelope stamp columns, so falsification 24 asserts the ROW
  projection only; its comment says so, and stamp survival rests on the unit assertion plus the SQL
  above. Do not upgrade that comment into a claim.
- **Product wart, needs an ask before touching:** the throttler guard throws instead of emitting, so a
  user who burns the link cap gets silence and a hanging link UI — unlike every other refusal here.
- `markConversationRead` drives the ROW to READ but does not stamp envelope `readAt` (pre-existing,
  independent of T7; the app-proof row shows `readAt` NULL while the row is READ).
- Still open from earlier tickets: falsification 12 and `list_device_mismatch` are unit-proven only, the
  §6.2 reset teardown has never run against a live account, and T5's killed-ack reconcile is
  suite-covered only.

## Verified at `7c297c2`

backend **990/61** · ratchet **886** real (floor 906, PASS — typing the edit handler removed 20 more
unsafe-access findings than the ticket added) · analyze clean · flutter **1519/10sk** · wire **43/2sk** ·
both count verifiers OK.
