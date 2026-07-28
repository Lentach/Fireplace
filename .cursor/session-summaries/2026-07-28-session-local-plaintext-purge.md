# 2026-07-28 — Local plaintext purge: deleted and expired messages now actually die on the device

Branch `audit/e2e-safety` (separate worktree). **Not deployed, not bumped** — live stays 0.0.132.
Continues the 2026-07-27 E2E audit. Owner's framing: "chat with 100% sure nobody can read that
messages... all my messages are saved when they should be gone irreversible".

## The bug, restated correctly

The persisted plaintext record is the **ONLY copy** of a message. The server keeps ciphertext whose
Double Ratchet message key was consumed at first decrypt, so re-decryption is impossible
(`encryption_service.dart` documents this and the bob210 field case). Consequences that drove every
decision:

- Purging is permanently irreversible. No undo, no server fallback.
- Deleting/expiring a message removed it from the server and the UI but **never** from the device.
- Destroying too EARLY is unrecoverable data loss; too LATE is minutes of extra exposure. Everything
  is therefore biased to destroy late.

## What was wrong, beyond the original report (#105)

1. **Expiry was worse than delete.** `removeExpiredMessages` is RAM-only AND returns early when
   nothing expired in memory, so anything expiring while the app was closed left a record no code
   path would ever revisit.
2. **NEW, and the most damaging: the 2000-entry LRU eviction was silently destroying history.**
   Eviction is not deletion — the server row stays alive and `hiddenByUserIds` doesn't filter it, so
   the row re-serves as `[encrypted]`, re-decrypt hits `DuplicateMessage`, and it bricks to a
   permanent `[Decryption failed]`. For any account past 2000 messages this fires constantly. A
   plausible source of previously-unexplained decrypt-failure reports.
3. **Purging by loaded rows is insufficient.** History pages ~50 rows while the store holds 2000
   across sessions, so "clear chat history" on a fresh launch would purge the visible page and
   strand the rest forever (no expiry, no conversation index).
4. **Unfriend/block purged nothing at all** — not RAM, not disk.
5. **Local-clock expiry purging is itself a loss hazard.** Client uses `DateTime.now()`, server uses
   `CURRENT_TIMESTAMP` + a per-minute cron. A fast clock destroys plaintext for live messages.
6. **The `Date` header cannot supply a server clock** — cross-origin and not CORS-safelisted, so the
   browser strips it and the gate would have silently never fired on web, the platform this is for.
7. Decrypted **voice notes** (`audio_cache/<id>.audio`, native) were never removed and are swept
   into OS backup.

## What shipped

- Per-id purge + conversation purge by **prefix scan on a stamped `_cid`** (records now carry
  `_cid/_savedAt/_createdAt/_expiresAt/_disappearAfter`). Wired into delete, clear-history,
  delete-conversation, and unfriend/block.
- **Two-phase expiry:** hide on the local clock (reversible), destroy only against a confirmed
  `ServerClock` plus a 5-min grace covering the cron. `socketReady` now carries `serverTime`
  (**wire contract, CLAUDE.md §7**); absent field ⇒ client holds and never destroys. Fail-safe.
- `_expiresAt` **re-stamped on `messageDelivered`** — read-mode messages get their deadline *after*
  the record is written, so a sweep keyed on `_expiresAt` alone would have missed exactly the
  messages with a timer set.
- **Durable purge backlog** (`e2e_<uid>_purge_pending_v1`) written BEFORE anything is touched,
  cleared only on confirmed completion, under the cross-context lock. Makes purging at-least-once
  across tab close. Its own write is commit-checked (`PURGE_BACKLOG_WRITE_FAILED`) so "failed, will
  retry" is distinguishable from "failed, now lost".
- **Every removal gated on its commit result.** `removeDecryptedContent` / `clearDecryptedContentCache`
  return result objects with `isComplete`; the UI never reports success on residue. This is the
  guarantee the whole change rests on.
- **Retired-id set** for the three paths that destroy plaintext while the server still serves the row
  (retention, LRU eviction, early expiry) — keeps them out of the decrypt path and renders a
  deliberate "no longer stored on this device" state instead of `[Decryption failed]`.
- **30-day retention**, ageing from a one-time epoch key so existing history fades over the
  following window instead of being mass-destroyed on upgrade.
- Real **"delete all local history"** action, distinct from the audio-cache row, two-step confirm.
  The previous button touched text plaintext on **no** platform and was a total no-op on web.
- `TZ: UTC` pinned in both compose files — `expiresAt` is `timestamp WITHOUT time zone`, so a
  non-UTC backend ships deadlines shifted by the host offset and the client would destroy plaintext
  hours EARLY. Found by running the backend on a UTC+2 host: the 15-min edit window also read as
  expired immediately (that was the only e2e failure, and it was environmental, not a regression).

## Two-axis review, and what it caught

Ran the repo's `code-review` skill over `de7b7a6...HEAD`. **Standards: 0 hard violations** (one
judgement call — the new sentinel is a raw literal like the existing ones; left alone, since
`message_model.dart` cannot import a provider constant without inverting the layering).
**Spec: 2 real gaps, both fixed:**

- `CLAUDE.md` §6 still claimed uninstalling the PWA destroys device keys — the exact false warning
  #105 was filed against, and it points users at clearing site data, which is what actually loses
  their history. Rewritten to say what does and does not destroy keys.
- The wipe copy said "cannot be recovered". Scoped to the server that is true, but it is the
  phrasing this work explicitly warned against, so it now reads "cannot be undone … no copy to
  restore from" — accurate about the product without claiming the bytes are gone.

Two races surfaced in the same pass and were fixed: retired ids were loaded on `socketReady`
**unawaited**, racing the first history pass (losing that race persists a permanent
`[Decryption failed]` for a row the app purged on purpose) — now loaded in `initializeE2E`
**before** `_e2eInitialized` flips, the only point that provably precedes any decrypt; and
`clearAll()` / `onConnect(false)` never cleared `_retiredIds`, so on account switch the previous
account's ids stayed live.

## B2 started: the record envelope (`plaintext_record_codec.dart`)

Format + constraints only — **nothing seals anything yet**, no storage change, no migration.
Metadata stays cleartext (every sweep selects on it); payload is what gets encrypted. Codec is now
the single owner of the metadata key names, with `encryption_service` aliasing them.

Three constraints written into the file because they are easy to get wrong and expensive to get
wrong:

1. **Durability inverts.** These records are in localStorage *because* its writes are synchronous
   and survive a tab close; the content key would live in IndexedDB, whose in-flight transactions
   are **aborted** by a tab close. Mint → encrypt → write record → persist key can land ciphertext
   and lose the key, leaving records unreadable forever, silently. It also flips the blast radius:
   one lost plaintext record costs one message, a lost content key costs **every** message at once.
   Hence: persist the key, read it back from a **fresh** transaction, and only then arm sealing.
   Until armed, keep writing cleartext.
2. **Migration is incremental and resumable** — not one atomic rewrite (2000 only-copies must not
   half-fail) and **not lazy on read** either: lazy would leave the OLDEST records cleartext, and
   those are exactly the ones retention destroys first, so their residue would never be shredded.
3. **Rotation is the piece that carries the promise.** Encryption at rest alone gives "unreadable
   without the key" — but the key is live, so purged records still sit decryptable in the LevelDB
   WAL. Only rotating and destroying the key on purge turns residue into ciphertext under a key that
   no longer exists. **"Encrypted at rest" ≠ "shredded".** Do not conflate them when reporting.

## Verification

- analyze **0 issues**; `flutter test` **956 passed / 5 skipped** (counts machine-verified);
  backend **541/47**; `flutter test test_e2e` **12 passed / 2 skipped** vs a real backend.
- New e2e test: real server `deleteMessage` → plaintext destroyed → **Signal session still alive**
  (the risk was never that delete fails, but that purging also bricks the conversation).
- Refused-commit tests install a `SharedPreferencesStorePlatform` whose `remove` returns false —
  the only way to exercise the honesty guarantee. **Found while doing it:** `prefs.remove` drops its
  in-memory cache entry even when the backend refuses, so within a session the row reads as gone
  while bytes remain. That is precisely why retry must come from the durable backlog.
- **Live browser proof** (release build, real backend, real localStorage, uid 23): seeded a record
  expired 1 h ago, a control expiring in 24 h, and a backlog entry. After reload — expired
  **destroyed**, control **intact**, backlog target **destroyed**, backlog key **cleared**, and all
  **26 `sig_e2e_23_*` Signal keys untouched**. `e2e_<uid>_retention_epoch_v1` existing at all proves
  the sweep ran, since only the sweep writes it and it returns early without a confirmed clock.
- ConnectionProvider wiring test **falsified both ways**: commenting out
  `_runLocalPlaintextMaintenance()` turns both new tests red.

## Notes for next session

- **NOT deployed, NOT bumped.** CI has never run on this branch — open the PR to run it.
- ⚠ Rebase onto `origin/master` (`59d80ae`); the `CLAUDE.md` count line will conflict.
- **B2 (at-rest encryption + key rotation) is NOT built, and it is the remaining half of the
  owner's actual ask.** This change delivers "gone from the app", not "gone from the disk":
  localStorage is LevelDB and `removeItem` leaves the value in the WAL until a compaction we do not
  control; flash wear-levelling means a file delete is not a shred. Genuine unrecoverability needs
  records encrypted under a key that is **rotated and destroyed on purge**, so residue becomes
  ciphertext under a key that no longer exists. Design agreed: `{kid, iv, ct}` envelopes, both keys
  live during rotation, old key destroyed only after a full scan proves zero references — a
  half-finished rotation must be resumable state, never data loss.
- **Never describe the current state as "cannot be recovered."** That would repeat the exact defect
  this work removed: an operation claiming a stronger destruction than it performs.
- Local stack notes: another worktree holds :3000/:5433, so this one ran on **:3100 / :5533**
  (`docker compose -p fireplace-audit -f docker-compose.yml -f <tmp>/ports.yml`). The backend ran on
  the HOST with `TZ=UTC` because `nest start --watch` never bootstrapped inside the bind mount.
  `flutter run -d web-server` bundles do not survive a tab reconnect — **build a release bundle and
  serve it statically** for browser work.
- `CLAUDE.md` §6 uninstall claim is still wrong (tracked in #105).
