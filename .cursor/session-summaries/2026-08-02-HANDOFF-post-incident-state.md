# HANDOFF — post-incident state, open work, and the traps that bite

**Written:** 2026-08-02. Read root `CLAUDE.md` first, then this, then `frontend/CLAUDE.md` before touching Flutter. The `[Decryption failed]` P0 is **CLOSED and confirmed in the field** — do not re-open that investigation.

Every fact below was verified by a command at write time. Re-verify anything volatile before you act on it (root `CLAUDE.md` §1).

## State of the world (verified 2026-08-02)

| | |
|---|---|
| Prod frontend | `0.0.140 / 3a33bf9` (`/version.json`) |
| Prod backend | `0.0.136 / 6fb36bf` — **by design**, frontend-only releases since |
| `master` | `70eff73` (prod runs `3a33bf9`; `70eff73` is docs-only on top) |
| `feature/android-encrypted-store` | **level with master as of `70eff73`** — re-derive the tip with `git rev-parse`, never trust a pinned SHA here |
| Open PR #111 | Android Phase 2 → master. **Do not merge without owner OK.** |
| PRs #113–#119 | Dependabot, untouched |

Worktrees: owner's main copy `C:/Users/Lentach/Desktop/Fireplace` (on the Android branch, **behind — needs `git pull`**), `fireplace-e2e-audit` (stale, `audit/e2e-safety`, merged long ago — removable), `fireplace-wt-invitation` (master, the one to work in).

**The PWA is the owner's live workstation with ~25 real conversations.** It is not a test surface. Android ships first, then iOS; the PWA stays for iOS until then.

## What the incident was, in one paragraph

`SharedPreferences.reload()` reads the store, awaits, then clears its in-memory cache and refills it from the snapshot it took. A write landing inside that window survives on disk but is dropped from the cache, so `getString` answers null for a record that is physically present. For a plaintext record that false miss is not "no plaintext" — the caller re-decrypts a ciphertext whose Signal ratchet key was consumed at first decrypt, hits `DuplicateMessage`, and the row becomes a permanent `[Decryption failed]`. The window is **web-only** and pre-existed; 0.0.136's new concurrency (60s sweep timer + drain/sweep/reconcile at every socketReady) is what made it fire. Fixed in 0.0.139 by reading the backing store instead of the cache; confirmed by several days with zero new reports.

Full detail: `2026-07-29-session-decryption-failed-root-cause.md`. The four hypotheses in `2026-07-29-HANDOFF-decryption-failed-incident.md` are **all dead, killed by measurement** — that file is historical, do not work from it.

## DO NOT "restore consistency" here — three deliberate asymmetries

These look like inconsistencies. They are load-bearing. Changing any one of them re-arms data destruction.

1. **`storedMessageIds()` reads the CACHE, on purpose.** It is the sole input to `reconcileStoredPlaintext`, which purges every id the server does not list back. Expired rows *are* hard-deleted server-side by a per-minute cron, so orphans genuinely exist. Under-enumeration means reconcile asks about **fewer** ids and purges **less** — the safe direction.
2. **`_messageIdsMatching` is split by an `authoritative` flag.** `messageIdsForConversations` (delete / clear history / unfriend / block) passes **true** — the user asked for that plaintext to be gone, so missing a record on disk leaves readable history behind. `destroyableMessageIds` (expiry + retention sweep) passes **false** — nobody asked, and under-enumeration merely delays destruction.
3. **The LRU prune counts via the cache.** It under-counts, which suppresses eviction. Eviction calls `markRetired` and is permanent; making it authoritative could retire an account's oldest history on the first launch after the change.

Governing rule, established across this incident: **over-retention is recoverable, over-destruction is not.** Every destructive rule must fail closed.

## Where the fix lives now

`ContentKv.authoritativeSnapshot()` — added when master was merged into the Android branch, so the concept belongs to the storage seam rather than to `EncryptionService`.

- `PrefsContentKv` answers on web only. `reload()` already pays for that same `getAll()`, so it is free there. **This backend also serves iOS, desktop and the Android fallback**, so the `kIsWeb` gate must stay inside it — unconditional would be a full method-channel serialisation of the whole map per decrypted message.
- `NativeContentStore` answers null: single process, and `reload()` never clears `_view`, so the clobber window cannot exist on the encrypted store. **Android was never affected by this bug.**
- `PrefsContentKv.debugForceAuthoritative` exists because `flutter test` runs on the VM with `kIsWeb` false. Without it the reload-race suite exercises the cache path and passes while proving nothing.

**Falsify that suite before trusting it.** Set `debugForceAuthoritative = false` and confirm the single read, the batched history read and the user-requested delete go red with `Actual: <null>` / `Actual: Set:[]`. Green alone means nothing — the harness can stop reproducing.

## Open work, highest value first

1. **The ledger — "messages I have already decrypted once".** Just ids, tiny. Today a lost record and a deliberately deleted record are indistinguishable to the app, so it retries decryption and bricks the row. With a ledger: id present + no plaintext ⇒ "unavailable, ask sender to resend", never re-decrypt. **This is what makes aggressive deletion safe instead of one bug away from repeating the incident.** `markRetired` is already shaped like this; it just isn't applied to the general case.
2. **Encrypted at-rest store (Android Phase 2, PR #111).** The real exposure and the actual distribution blocker. Message plaintext is readable on disk today — base64 in localStorage on web, raw XML on Android. No key, no cracking. Perfect deletion still leaves up to 30 days sitting there.
3. **Note expiry cron.** `secret-notes.service.ts` deletes expired notes `@Cron(EVERY_DAY_AT_3AM)`, so an **unread** expired note's ciphertext lingers up to ~24h past TTL. The API refuses to serve it, but the AES key lives in the note URL, which is stored as ordinary plaintext message content — so DB access + device access reads a "self-destructed" note. One-line change to match `MessageCleanupService`'s per-minute cron.
4. **`delete for me` leaves the server row forever.** The server never checks whether *both* participants hid a row, so a message both sides deleted sits there until expiry. It cannot drop it on the first delete because the other participant still needs to read it.
5. **The expiry sweep logs nothing on success.** That gap made the incident diagnosis much harder than it needed to be. Add success-side diagnostics.

## Before an APK ships — a real gate, not a nicety

`CONTENT_KEY_CANARY_LOST` in field diags means the encrypted store **must not ship on that storage**: the SQLCipher key comes from the same place the canary measures. Canary shipped 2026-07-28; the window is open now. I nearly deleted this gate while trimming `LATEST.md` for its size budget — it is recorded as an open item there.

## Traps that cost time this session

- **`sed` with `$` anchors silently no-ops on this CRLF repo** (`pubspec.yaml`, test files). It reports success and changes nothing. Use the edit tool.
- **`flutter test --platform chrome` hangs at load** (dart2js + libsignal). 15 minutes, no output. Do not try to prove web behaviour that way; use a test seam instead.
- **CI only runs on `master` pushes and PRs.** A feature-branch push gets no run at all — open a PR to get CI.
- **`deploy-web.ps1` builds the checkout it lives in**, not your cwd and not master. Deploy from a worktree that is on the commit you intend to ship, and confirm the smoke's expected commit.
- **`post-deploy-smoke.mjs` defaults to the working copy's HEAD.** Pass `--commit <sha>` when checking anything else, or it reports a false stale-build failure.
- **The pre-commit hook enforces the `LATEST.md` size budget** (≤5 entries, ≤2600 words). A merge that combines both sides' entries will breach it; compact the oldest to a pointer — but read what you are deleting first, one of those bullets was a live gate.
- **`E2ePersistentDiag` is capped at 80 entries** and rotates. In an incident, get the dump before anything else; evidence from the failure window may already be gone.

## Rules the owner holds you to

- **Never uninstall, never clear site data.** That destroys Signal keys and all history, irreversibly.
- **Never deploy or merge to master without explicit OK.** I broke this once with a rollback and it cost real trust.
- Lead with the verdict, no hedging, no flattery. Say "I don't know" rather than dressing up an inference as proof — this owner checks.
- Distinguish **mechanism proven** from **cause proven**. State which one you have.
