# Dependabot swept to zero (7 alerts, 12 PRs), majors ruled with evidence, dependabot.yml fixed — plus a PC health pass

**Date:** 2026-09-08 (after the D26 merge/deploy)

Owner's ask, in two parts: *"resolve dependabot pull request and security and quality 7 conflicts"*, then
*"also update anything that can be updated without breaking the app"*, then *"check if anything on this pc can be
updated too, do a health check … or if something is blocking"*.

The "7" was exact: **7 open Dependabot security alerts** (#107, #109, #110, #111–#114). The "conflicts" were real
too — the three fixing PRs all rewrite `backend/package-lock.json`, so merging any one of them puts the other two
into conflict. That is why none of them was merged.

## What was done

### Dependency work — end state: 0 open alerts, 1 open PR (parked on purpose), 0 open code-scanning alerts

Master went from `01cff73` to **`084774e`** in five commits:

| Commit | What |
|---|---|
| `e26c3ac` | fast-uri 3.1.5→3.1.7, qs 6.15.3→6.16.0, browserslist 4.28.5→4.28.9 **in one lockfile edit** (closes all 7 alerts), plus every remaining in-range update via `npm update`: multer 2.2.0→2.3.0 (4 CVEs), pg 8.22.0→8.23.0, typeorm 1.1.0→1.1.1, undici 7.29.0→7.29.1, `@nestjs/*` 11.1.28→11.2.3, jest 30.4.2→30.5.1, eslint 10.8.0→10.10.0, typescript-eslint 8.65.0→8.70.0, `@types/pg` 8.20.0→8.23.1, `@eslint/eslintrc` 3.3.6→3.3.7. No package.json constraint changes. |
| `7d2693b` | dependabot.yml: ignore `@types/node` and `@nestjs/*` **majors**, each with its removal condition inline. |
| `4a948c5` | firebase_core ^3.8.0→^4.14.0, firebase_messaging ^15.1.6→^16.6.0, flutter_local_notifications ^22.2.0→^22.3.0. |
| `279df93` | globals 16→17 (eslint global sets only). |
| `090b67f` | google_fonts ^6.3.3→^8.2.1, emoji_picker_flutter ^4.5.3→^4.5.4. |
| `084774e` | dependabot.yml: **pub group removed**, `clock` + `build_runner` ignored, and the drift/sqlite3 rationale CORRECTED. |

**Applied because the evidence said safe.** The two that needed real proof:

- **firebase_core 4 + firebase_messaging 16** — CORRECTED WORDING (verified in the pub cache): the plugins do
  NOT pin their own SDK levels when built inside an app — `firebase_core-4.14.0/android/build.gradle:43-47` and
  `firebase_messaging-16.6.0/android/build.gradle:42-45` read `project.ext.compileSdk` / `project.ext.minSdk` /
  `project.ext.targetSdk`, i.e. they INHERIT ours (36 / 24 / 36). Their standalone fallback
  `android/local-config.gradle` says compileSdk=34 / minSdk=23 / targetSdk=34 / Java 17, which is only used when
  the plugin is built on its own. Either way nothing is above us — unlike `permission_handler_android` 14.1.0,
  which HARDCODES `compileSdk = 37` with AGP 9.0.1 + Kotlin 2.3.20 (`android/build.gradle.kts:5,12,31`). So the
  gradle read is not the proof; the green `flutter build apk --debug` is.
  `firebase_messaging` 16.0.0's only removed Dart API is `sendMessage()`, which this app never calls. Web is
  untouched: init is `!kIsWeb`-gated, web push is our own `web-push-sw.js`, `web/index.html` pins no Firebase JS.
  Proof: **`flutter build apk --debug`** (assembleDebug 458.9 s, green) on top of analyze + suite + web release
  build — the host suite alone proves nothing here, since `push_service.dart` returns early on `kIsWeb`.
- **google_fonts 6→8** — both majors exist ONLY to delete font families, and none of the deleted ones is used
  (`GoogleFonts.inter`, `.archivo`, `.pressStart2p`). No `*TextTheme()` helper and no `GoogleFonts.config`, so
  8.2.0's `Config`→`GoogleFontsConfig` rename does not reach us; fonts are runtime-fetched (no `fonts:` section).
  **A green suite cannot see a silent font fallback**, so rendering was checked twice: the API returns real
  per-weight families (`Inter_600`, `Archivo_900`, `PressStart2P_regular`), and the served release bundle really
  fetches five `fonts.gstatic.com` TTFs in a headless browser. Not verified: a pixel diff vs 6.3.3.

**Refused, each with the blocker named (all recorded on the PRs):**

| Refused | Blocker |
|---|---|
| `@types/node` 26 (#155) | Runtime is `node:22-alpine` in BOTH Dockerfile stages, CI pins node 22, `engines.node >=22`. Types for 26 would let a missing-API call type-check green and crash in prod. |
| `@nestjs/platform-express` 12 (#156) | Needs core+common ^12; `@nestjs/throttler@6.5.0` (latest) still peers `^11` only → Nest 12 breaks the WsThrottlerGuard contract (§7). Dependabot's partial bump failed its own CI. |
| `firebase-admin` 14 (#167) | **Probed 14.3.0: `admin.messaging` and `admin.credential` are `undefined`** — the legacy namespace is gone. `push-notifications.service.ts` uses `admin.apps`/`initializeApp`/`credential.cert`/`messaging().sendEachForMulticast`. Needs a modular rewrite + a live FCM round-trip; the unit tests mock the module, so they would go green on a wrong rewrite. |
| `undici` 8 (#168) | 8.0.0 is `feat!: enable h2 by default` + legacy-handler removal, on the SSRF-pinned link-preview fetch path (custom CONNECT-time `lookup`), and our tests stub fetch. Also raises `engines.node` to >=22.19.0. Zero advisory benefit: 7.29.1 is clean. |
| `typescript` 7 | ts-jest peers `typescript >=4.3 <7`; typescript-eslint peers `>=4.8.4 <6.1.0`. |
| `permission_handler` 13 (#158) | `permission_handler_android` 14.1.0 declares `compileSdk = 37` with AGP 9.0.1 + Kotlin 2.3.20 — an Android toolchain migration. (Also: 14.x makes `Permission.status` never return `permanentlyDenied`; our one call site reads `isGranted` then requests, so it would survive.) |
| `clock` 1.1.3 | `flutter_test` from the SDK pins clock 1.1.2 — unresolvable. |
| `build_runner` 2.16.x | Wants analyzer >=13.3.0 (needs meta ^1.18.3 vs SDK's 1.18.0) AND is capped by drift_dev 2.31.0's analyzer <11.0.0. |
| `drift` 2.34 / `drift_dev` 2.34.6 / `sqlite3` 3.5.2 | They resolve, then `flutter analyze` fails: **sqlite3 3.x deleted `package:sqlite3/open.dart`**, imported by `content_db.dart` for the SQLCipher open override. |

### The dependabot.yml bug that was manufacturing dead PRs

`ignore` for drift/drift_dev/sqlite3 has been in the file since **2026-08-03**, yet **#157 (09-01), #169 and #171
(both today)** each bundled them anyway — and every one of those PRs was unresolvable. That matches
dependabot-core #7523 / discussion #11962 for a group with no explicit `patterns`. Fix in `084774e`: the
`frontend-minor-patch` **group is gone** (update-config-level `ignore` does work for standalone PRs), and `clock`
+ `build_runner` joined the ignore list with their SDK-pin reasons and a "re-check after a Flutter SDK upgrade"
note. Cost: up to 3 frontend PRs/month instead of 1 grouped one — cheaper than a permanent dead PR.

**⚠ THE FIX IS UNPROVEN — do not inherit it as settled.** Right after `084774e` was pushed, dependabot opened
#172/#173/#174 at 14:23, all with **base sha `084774e`** — and **#173 is STILL titled "frontend-minor-patch
group"** and still bundles drift 2.34.4 / drift_dev 2.34.6 / sqlite3 3.5.2 / build_runner 2.16.1 / clock 1.1.3,
i.e. the exact set the ignore list names. Either that run read a cached config or the group shape survives the
config change. The shape only proves out on the NEXT dependabot run: if a grouped `frontend-minor-patch` PR
appears again, the yml is not the enforcement point and the server-side route (`@dependabot ignore this <x>
version` comments, which are stored per-repo) is. That route was used on #155 and #156 as belt-and-braces.

What that run DID show, and it is the expected new shape: per-package PRs. #172 permission_handler 13.0.2 (same
compileSdk-37 blocker, closed), #173 the blocked five (closed), and **#174 file_picker 11.0.2 → 11.0.3, LEFT
OPEN on purpose** — that is the attachment picker (`chat_action_tiles.dart`), and `utils/web_file_input.dart`
exists precisely because of file_picker 11.0.2's web DOM behaviour (its comment: file_picker styles the `<input>`
`display:none` and REMOVES it from the DOM). The 2026-08-19 composer rule applies: nothing ships there without a
green repro and the owner's explicit OK, and no host test can see that DOM path.

Also **corrected a wrong comment** in that file: the drift/sqlite3 pins were justified by a native-assets hook
"demanding CMake + MSVC C++ on every local `flutter test`". That does not reproduce — the full host suite runs
fine with sqlite3 3.5.2 resolved. The real blocker is the deleted `open.dart`. Source beat the note.

### PC health pass (two read-only diagnostic agents, then only zero-regret actions)

Applied: **killed a runaway `dllhost.exe`** (PID 4936, AppID `{DFB65C4C-…}`, all modules System32 — it had burned
**4,033 s of CPU since 06:09**, ~one full core, 8 threads); **freed 9,063 MB** by deleting 297 leaked
`flutter_tools.*` dirs older than 2 days from `%TEMP%` (12.6 GB → 2.2 GB; C: 226.8 → 232.9 GB free); **upgraded
the safe set** via winget — GitHub CLI 2.92→2.100, .NET 8 Runtime/ASP.NET/Desktop 8.0.14→**8.0.30** (16 patch
levels of security fixes), CMake 4.3.4→4.4.3, App Installer 1.29.289→1.29.290. 23 winget upgrades → 16 remaining.

**The machine is capacity-bound, not fault-bound**, and two things are genuinely wrong — see "Notes" below.

## Key files

- `backend/package-lock.json` — the 7-alert fix plus the in-range refresh (no `package.json` changes except globals).
- `backend/package.json` — globals `^16.0.0` → `^17.12.0` only.
- `frontend/pubspec.yaml` / `frontend/pubspec.lock` — firebase_core ^4.14.0, firebase_messaging ^16.6.0,
  flutter_local_notifications ^22.3.0, google_fonts ^8.2.1, emoji_picker_flutter ^4.5.4. `version: 0.2.23` untouched.
- `.github/dependabot.yml` — backend major ignores; pub group removed; clock/build_runner ignored; corrected comment.
- PRs closed with the evidence written INTO each thread: #154, #155, #156, #157, #158, #159, #160, #161, #162,
  #166, #167, #168, #169, #170, #171, #172, #173. **#174 (file_picker) is deliberately OPEN** — owner's call.

## Verification

- **Backend**: `npm ci` + `nest build` clean; **jest 1096/1096 in 62 suites**; `npm audit` **0 vulnerabilities**;
  `node scripts/verify-claude-backend-test-counts.mjs` OK; `node scripts/lint-ratchet.mjs` **PASS** (894 real /
  157 formatting, unchanged — typescript-eslint 8.70 first reported −14 against the pre-D26 baseline).
- **Frontend**: `flutter analyze --no-fatal-infos` clean; **`flutter test` 2027 passed / 14 skipped**;
  `flutter build web --release` OK; **`flutter build apk --debug` OK** (the Firebase-major proof).
- **CI on master**: `084774e` **CI completed/success** — that run is what covers the google_fonts/emoji_picker
  commit, whose own run (`090b67f`) was CANCELLED by the next push, as was `e26c3ac`'s (its Backend tests /
  E2E wire harness / E2E isolated probes / Web Lock probe were green before cancellation). `279df93` green too.
  Read run state with `gh api repos/Lentach/Fireplace/commits/master/check-runs` or
  `?head_sha=<sha>` — plain `gh run list --branch master` returned stale rows (commits from weeks ago) twice
  this session and must not be trusted for "is master green".
- **`dependabot/alerts` open count `0`** and **`code-scanning/alerts` open count `0`**; `gh pr list --state open`
  → **`174` only** (parked file_picker). Everything else from three dependabot waves is closed with evidence.

## Notes for next session

- **PROD DOES NOT HAVE ANY OF THIS.** Live is still `0.2.23` from `65affc8` (frontend) / `302006e2` (backend);
  master now carries undeployed dependency changes on BOTH tiers. The next frontend deploy ships **firebase_core 4
  + firebase_messaging 16 + google_fonts 8** → bump PATCH, and re-run the FCM check on a real device/emulator
  (native build is proven, a live push round-trip is NOT). The next backend deploy ships the lockfile refresh
  (multer 2.3.0 changes multipart edge behaviour: exact-`fileSize`-limit files now accepted, WHATWG-escaped
  `originalname` decoded) — smoke the media upload path.
- **Two follow-up tasks, both scoped and blocked on nothing but time:** (1) firebase-admin 14 = modular rewrite of
  `push-notifications.service.ts` + re-verify the `messaging/registration-token-not-registered` code under the
  14.0.0 "Error Handling Revamp", acceptance = live FCM. (2) undici 8 = needs link previews exercised against real
  hosts (incl. an h2-only origin and an SSRF refusal) to accept h2-by-default.
- **Nest 12 is a one-package wait:** everything else in the family publishes ^12 peers; `@nestjs/throttler` does
  not. Re-check it, then move the whole family in ONE PR and delete the ignore rule.
- **Known flake, cause found, not fixed:** `test/services/unread_badge_sync_test.dart` → "falls back to the window
  Badging API when the push SW is absent". The harness pairs `debounce: 1 ms` with a fixed
  `Future.delayed(20 ms)` (lines 52-53) and that case needs two such windows plus one extra await, so it loses
  under a loaded parallel runner. Deterministic fix: fake_async or poll-until-condition; no assertion in the file
  cares about elapsed time, only ordering.
- **PC, needs an owner decision (security):** **nothing is protecting this box.** `Get-MpComputerStatus` →
  `AMRunningMode = Not running`, real-time protection False, `WinDefend` Stopped/Manual; SecurityCenter2 lists
  Kaspersky 21.24 but service `AVP21.24` is Stopped with StartMode Auto and zero `avp*` processes. Defender stood
  down for Kaspersky; Kaspersky never starts. Pick one owner. If AV comes back, add exclusions FIRST for
  `.gradle` (8.8 GB / 97k files), `Pub\Cache` (1.1 GB / 53k), `npm-cache` (3.0 GB / 44k), `Android\Sdk` (10.1 GB /
  95k) or every build pays the scan.
- **PC, hardware/reliability:** 5 × Kernel-Power 41 + EventLog 6008 pairs since 07-12 (08-31, 08-22, 08-04, 07-18,
  07-12) with **no** BugCheck 1001 → looks like power loss / hard reset, not a software crash. Check PSU/mains, or
  a UPS. Volsnap 36: shadow copies on C: are aborting ("storage could not grow due to a user imposed limit") →
  System Restore has no rollback point; `vssadmin resize shadowstorage /for=C: /on=C: /maxsize=25GB` (admin).
  SSD wear/temperature could NOT be read (`Get-StorageReliabilityCounter` needs admin) — worth one elevated run,
  C: is a budget 1 TB Goodram taking all dev I/O.
- **PC, capacity:** 16 GB RAM is the binding constraint (measured 530 MB available with Comet's 28 processes at
  4.8 GB; 7.9 GB available once closed). 4× 4 GB dual-channel at rated 2133 — an upgrade means REPLACING modules.
  CPU measured 100% then 83% with no downclock and High-performance plan already active: 4 cores is the ceiling,
  so do not run several worktree builds at once. `E:` is a 118 GB SSD sitting **99.9% empty** while all caches
  live on C: — relocating `GRADLE_USER_HOME` / npm cache / `PUB_CACHE` there is free parallel I/O.
- **PC, still updatable (deliberately skipped, they touch live tooling):** Git 2.53→2.55 (the installer replaces
  the very shell an agent session runs in — do it when the box is quiet), WSL 2.6.3→2.7.13 (kills the WSL VM and
  every container), OpenJDK 17.0.18→17.0.20 (note Flutter/Gradle uses Android Studio's bundled JBR 21, not this),
  Cursor 3.18→3.19, Python Launcher (winget maps 3.12 and 3.14 to the same id — ambiguous, fix the inventory
  first), Google Cloud SDK (manages itself via `gcloud components update`), Flutter **3.44.6 → 3.47.0** (3 minors
  = Dart SDK + engine + changed web output; must be its own tested migration), and the cosmetic set (Teams,
  Outlook, OBS, Obsidian, LibreOffice, PowerToys, PhysX, TeamSpeak, FACEIT, Ubisoft). Docker Desktop 4.90.0 and
  Chrome 152 are already current. **No reboot is pending**; Windows is 25H2 / 26200.9168, fully patched, and the 9
  queued optional Intel/Samsung driver updates (dated 2016/1970) should stay unchecked.
- **Two traps paid for this session.** (1) The `edit` tool resolves a RELATIVE path against the workspace root
  (`Desktop/Fireplace`, on `feat/passcode-lock`), **not** the cwd — a dependabot.yml edit landed in the wrong
  worktree and had to be moved. In a multi-worktree checkout, always give `edit` an ABSOLUTE path. (2) Master
  moved under the session mid-flight (D26 merged + deployed while the lockfile work was in progress); the fix was
  to park the subagent's dirty `frontend/pubspec.*`, rebase, and re-verify from scratch — `git rev-parse HEAD`
  before every commit, and never rebase a shared worktree while a subagent has it dirty.
