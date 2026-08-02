# HANDOFF — post-incident state, open work, and the traps that bite

**Written:** 2026-08-02. Read root `CLAUDE.md` first, then this, then `frontend/CLAUDE.md` before touching Flutter. The `[Decryption failed]` P0 is **CLOSED and confirmed in the field** — do not re-open that investigation.

Every fact below was verified by a command at write time. Re-verify anything volatile before you act on it (root `CLAUDE.md` §1).

## State of the world (verified 2026-08-02)

| | |
|---|---|
| Prod frontend | `0.1.1 / 8415b31` (`/version.json`) — **level with master**, smoke 5/5. Carries the decrypt ledger |
| Prod backend | `0.0.140 / da120460` — **DEPLOYED 2026-08-02**, `schema up to date`, no migrations ran. Carries the per-minute secret-note sweep |
| `master` | `8415b31` — **level with prod on both surfaces.** Android Phase 2 and the decrypt ledger are both live on web |
| `feature/android-encrypted-store` | **MERGED into master** via PR #111 on 2026-08-02. Branch ref preserved because the owner's working copy sits on it; delete only after he moves to master |
| PR #111 | **MERGED** (`ac880f6`), CI green 4/4 |
| Deploy | Both surfaces current. Backend `/version` reads `0.0.140` because that was the pubspec when it deployed — its CODE is level; that lag is the documented convention, not drift |
| 🔴 FCM off in prod | `FIREBASE_SERVICE_ACCOUNT` is **absent from `~/fireplace/.env`**, so `PushNotificationsService` logs "FCM disabled" at every boot. `google-services.json` IS tracked, so the APK will register a token the server can never push to — **Android notifications are dead until this is set.** Web Push VAPID is present and unaffected |
| PRs #113–#119 | Dependabot, untouched |

Worktrees: owner's main copy `C:/Users/Lentach/Desktop/Fireplace` (still on `feature/android-encrypted-store`, now merged — he should **switch it to `master` and pull**), `fireplace-e2e-audit` (stale, `audit/e2e-safety`, merged long ago — removable), `fireplace-wt-invitation` (master, the one to work in).

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

1. **~~The ledger~~ — BUILT 2026-08-02, not yet released.** `e2e_<uid>_ledger_v1` records ids whose plaintext was persisted at least once, so a missing record is now distinguishable from one never decrypted. `_decryptMessageAsync` consults it before touching the ratchet: definitely-absent ⇒ `markRetired` + "no longer stored" instead of a DuplicateMessage that burns the row. **Three fail-open rules hold it up — do not "simplify" them:** recorded only after a CONFIRMED commit of real plaintext (a failed write must never lock out the decrypt that would still work); absence is decided by the tri-state `recordExists`, never by `getDecryptedContent() == null`, which also returns null for an unbound user and for any caught exception; an edit drops the entry via `invalidateDecryptionCache`, because edited rows carry new ciphertext under the same id. Cap 3000 tracks the 2000-record store — eviction past that already goes through `markRetired`.
2. **~~Encrypted at-rest store (Android Phase 2)~~ — DONE.** Merged (`ac880f6`) and **live on web since `0.1.0 / a60610f`**; no APK distributed. Android seals content in SQLCipher with Keystore-held keys; web/desktop keep the prefs path through the same `ContentKv` seam. Before an APK reaches anyone: **FCM service account on the VM** (see the state table — this is the new blocker), the owner's real-phone smoke, and the `.jks` off-PC backup. **Web at-rest exposure is unchanged and still open:** message plaintext is base64 in localStorage, which is what the canary-gated B2 sealing effort would fix. That is now the largest remaining privacy gap.
3. **~~Note expiry cron~~ — DONE**, shipped in backend `0.0.140 / da120460`. `secret-notes.service.ts:53` is `@Cron(EVERY_MINUTE)`, matching `MessageCleanupService`, and the cadence is pinned by a fail-before-proven test. Do not relax it: at daily, an unread expired note's ciphertext lingered ~24h past TTL while its AES key sat in plaintext message content.
4. **`delete for me` leaves the server row forever.** The server never checks whether *both* participants hid a row, so a message both sides deleted sits there until expiry. It cannot drop it on the first delete because the other participant still needs to read it.
5. **The expiry sweep logs nothing on success.** That gap made the incident diagnosis much harder than it needed to be. Add success-side diagnostics.

## The canary gate — what it actually gates

**Corrected 2026-08-02. The earlier wording here said the canary blocks the APK because "the SQLCipher key comes from the same place the canary measures". That is wrong, and the code says so.**

`ContentKeyCanary.checkAndArm()` opens with `if (!_isWeb) return;` (`content_key_canary.dart:96`) — it is a **no-op on native** and its own class doc says why: it measures `flutter_secure_storage` on **web**, which is IndexedDB + WebCrypto, the backend `signal_stores.dart:11-15` abandoned after keys vanished across tab closes. On Android the same plugin is Keystore-backed, which `signal_stores.dart:17-18` calls hardware-backed and reliable. Same plugin API, different backend. The canary can produce no evidence about Android, and the Phase 1 summary already said so: "Native Android can seal WITHOUT the web canary gate."

So:

- **It does NOT gate the APK / PR #111.** Do not block Android on it.
- **It DOES gate web B2 sealing**, which is a separate effort that has not started. Keep it. Do not "clean it up" because Android shipped without it.
- **Nobody can check it remotely.** `E2ePersistentDiag` is a capped SharedPreferences list read only by `privacy_safety_screen.dart` — display, copy, clear. There is **no upload path**, so "watch field diags" means exactly one thing: the owner opens Privacy & Safety in hacker mode and dumps it.
- **Absence of the event is weak evidence.** The durable log caps at 80 and rotates, and it was observed *exactly at cap* during the P0 incident — so a `CONTENT_KEY_CANARY_LOST` from late July may well have been evicted by incident spam. A clean dump means "no surviving evidence of loss", not "the storage is safe".
- **"Not canary-gated" is NOT "safe".** Phase 1 said the permissive half and the caveat in one breath, and only quoting the first half is the misread this section exists to stop: Keystore keys still die — factory reset, new-device restore, auth-binding invalidation — and the plaintext cache is **not re-derivable** (the ratchet consumed the keys; media records hold the only `mediaKey`/`mediaIv`). Content-key loss = the whole local history unreadable. The design budgets for it with four mitigations: **no auth binding, co-located with the Signal keys, the armed-gate (write → fresh read-back before use), and `CONTENT_KEY_LOST` → retired-id rendering.** The Android gate is that those four are present and tested — not that a canary went quiet.

The real Android gates are unchanged and none of them is the canary: the owner's real-phone smoke (voice play/seek/cached replay/legacy files, push, upgrade from a pre-Phase-2 install), the `.jks` off-PC backup (**still outstanding**), and his explicit merge OK.

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
