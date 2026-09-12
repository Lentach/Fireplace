# Stack-specific agent tooling for Flutter + NestJS (2026-09)

**Date:** 2026-09-10
**Sources:** primary only

Survey of tooling for agent-driven work on **this** stack: Flutter web/Android frontend
+ NestJS/Postgres backend, solo maintainer, public repo, E2E-encrypted messenger,
one 4 GB OVH VPS, Windows 11 dev box, OMP harness (Claude Code secondary).

Every entry carries provenance, install surface, egress, and a fit verdict. Popularity
is not a recommendation — several widely-used tools below are rejected on fit.

---

## 0. Baseline: what this repo actually is

Read from the repo, not assumed. These numbers drive several verdicts below.

| Fact | Value | Source |
| --- | --- | --- |
| Dart SDK floor | `sdk: ^3.10.7` | `frontend/pubspec.yaml:12` |
| Flutter local | 3.44 line → **Dart 3.12.2** | `releases_windows.json` (see Sources) |
| Flutter in CI | **unpinned** — `channel: stable` → Dart 3.13.3 today | `.github/workflows/ci.yml:122-124` |
| Lints | `flutter_lints ^6.0.0`, no extra rules enabled | `frontend/analysis_options.yaml:10-23` |
| Dart LOC | 55 806 in `frontend/lib`; 151 232 incl. tests | `wc -l` over `frontend/**/*.dart` |
| Backend | NestJS **11**, TS **5.7**, ESLint 10, Jest 30 + ts-jest | `backend/package.json:26-36,69-82` |
| Backend LOC | 38 893 (`src` + `test`) | `wc -l` over `backend/{src,test}/**/*.ts` |
| Realtime | `@nestjs/platform-socket.io` ⇄ `socket_io_client ^3.1.6` | `backend/package.json:32`, `frontend/pubspec.yaml:28` |
| Dep automation | Dependabot; pub ecosystem has `groups:` **deliberately removed** | `.github/dependabot.yml:45-55` |

Two version facts change the shape of everything below:

1. **Flutter 3.47 is current stable** (3.47.0 released 2026-08-12; 3.47.4 on 2026-09-11).
   The 3.44 line topped out at 3.44.9 / Dart 3.12.2 on 2026-08-06. There is no 3.45 or
   3.46 stable — so this repo is **one** stable release behind, not three.
2. **A local/CI SDK split already exists.** CI floats to Dart 3.13.3 while the dev box is
   on Dart 3.12.2. Any tool with an SDK floor between those two versions passes CI and
   fails locally. `very_good_analysis` 11 is exactly that case (§1.4).

---

## 1. Flutter / Dart side

### 1.1 Dart & Flutter MCP server (`dart mcp-server`)

- **What:** stdio MCP server exposing analyzer diagnostics, symbol resolution, test
  runner, `dart format`, pub search/add, and runtime introspection of a running app.
- **Provenance:** `dart-lang/ai` (Google), BSD-3-Clause, 283★, `pushed_at` 2026-09-11.
  Package `dart_mcp_server` **1.1.1**, published 2026-08-07, `sdk: ^3.12.0`.
- **Install surface:** ships in the Dart SDK — `{"command":"dart","args":["mcp-server"]}`.
  No separate install, no daemon.
- **Egress:** none. Local process, talks to the local analysis server / DTD.
- **Fit: already mounted, keep.** `sdk: ^3.12.0` is satisfied by Dart 3.12.2 (Flutter
  3.44.9), so the current pin is fine — **but there is no headroom**. Any bump of the
  server's floor to `^3.13.0` strands the local box until Flutter moves to 3.47.
  The July audit put Dart MCP "on probation"; the material change since is that it is
  now the *documented* centre of Flutter's whole agent story (§1.2), not a side project.

### 1.2 `flutter/agent-plugins` + `dart-lang/skills` (official skills & rules) — **new since July**

- **What:** Google's official agent-plugin marketplace. Four components: **agent skills**
  (progressive-disclosure `SKILL.md` recipes), **agent rules** (persistent context),
  MCP config, and **specialized agents**.
- **Provenance:** `flutter/agent-plugins`, BSD-3-Clause, **2 929★**, created 2026-02-25,
  `pushed_at` 2026-09-12. `dart-lang/skills`, BSD-3-Clause, 480★, `pushed_at` 2026-09-10.
  Installer package `skills` **1.0.1** on pub (2026-09-04, `sdk: ^3.10.0`).
- **Install surface:** for Claude Code, `claude plugin marketplace add flutter/agent-plugins`
  then `claude plugin install dart-flutter@dart-flutter`. Agent-neutral path:
  `npx skills add flutter/agent-plugins --skill '*' --agent universal --yes`, which writes
  plain `.agents/skills/` directories. Rules are **not** auto-loaded by Claude Code — you
  copy the ones you want from `agent-plugins/rules/` into `CLAUDE.md` yourself.
- **Egress:** install-time fetch from GitHub/npm only. Skills are local markdown at runtime.
- **Fit: recommended add, via the `npx skills` path, rules hand-picked.** The skills are
  files on disk, which is the one install surface that is harness-neutral — OMP can read
  `.agents/skills/` without depending on Claude Code's plugin loader. Caveat that matters
  here: these skills teach *generic* Flutter idiom (state management, responsive layout).
  This repo has hard local conventions (pinned `webcrypto 0.6.0`, `drift` upper-bounded,
  a vendored web QR path that must never fetch from a CDN) that a generic skill will
  cheerfully violate. **Do not bulk-install `--skill '*'` into rules.** Take skills as
  reference material; keep `CLAUDE.md` as the authority.

### 1.3 Developer Knowledge MCP (`developers.google.com/knowledge/mcp`)

- **What:** Google-hosted MCP server doing documentation search over docs.flutter.dev,
  dart.dev and API refs.
- **Provenance:** Google-operated hosted service. No repo, no version, no license to read.
- **Install surface:** remote MCP endpoint.
- **Egress: every query leaves the machine**, to Google, including whatever the agent
  puts in the search string.
- **Fit: reject.** A hosted doc-search MCP buys little that `read` on docs.flutter.dev
  does not already do (those pages serve clean `.md` alternates — this whole document was
  researched that way), and it adds an unbounded egress channel on a crypto codebase.
  Non-negotiable: no.

### 1.4 `very_good_analysis`

- **What:** Very Good Ventures' stricter lint rule set for Dart/Flutter.
- **Provenance:** `VeryGoodOpenSource/very_good_analysis`, MIT, 472★, `pushed_at`
  2026-09-03. **v11.0.0** released 2026-09-03, **`sdk: ^3.13.0`**. Previous v10.3.0
  (2026-06-18). 11.0.0 adds `async_return_with_no_await`, `empty_container_bodies`,
  `initialize_in_field_declaration`.
- **Install surface:** dev_dependency + one `include:` line in `analysis_options.yaml`.
  No daemon, no egress.
- **Fit: recommended add — but v10.3.0, not v11, until Flutter moves to 3.47.**
  This is the SDK-split trap from §0: `very_good_analysis: ^11.0.0` needs Dart ^3.13.0,
  which CI has (3.13.3) and the dev box does not (3.12.2). It would resolve green in CI
  and fail `flutter pub get` locally. `async_return_with_no_await` is directly relevant to
  a codebase whose ratchet/crypto paths are async-heavy. Sequence it: pin v10.3.0 now, or
  upgrade Flutter to 3.47 first and then take v11.

### 1.5 Flutter Widget Previewer — **graduated to stable in 3.47**

- **What:** `@Preview`-annotated widgets rendered live in a local server/IDE panel, with
  per-preview hot restart, theme/brightness/locale/textScale matrix, and search+filter.
- **Provenance:** in-SDK (`flutter/flutter`, BSD-3-Clause, 178 906★, `pushed_at`
  2026-09-12). Docs state "stable as of Flutter 3.47". 3.47 also landed local build
  caching (`.widget_preview/`) and preview search/filter.
- **Install surface:** `flutter widget-preview start` — local server + browser. No install.
- **Egress:** none (localhost).
- **Fit: recommended, and it is the strongest single reason to take Flutter 3.47.**
  The harness verification rule for UI change is "verify against the actual surface with
  a browser". Today that means booting the whole Flutter web app and navigating to the
  screen. `@Preview` collapses that to one annotated builder that an agent can render and
  screenshot directly — including dark mode and text-scale variants in one pass. Note
  `.widget_preview/` must be gitignored.

### 1.6 `patrol` — E2E, **and it now covers web**

- **What:** Flutter-native UI test framework with native-side automation (permission
  dialogs, notifications, app switching) that plain `integration_test` cannot reach.
- **Provenance:** `leancodepl/patrol`, Apache-2.0, 1 425★, `pushed_at` 2026-09-11.
  `patrol` **4.9.0** and `patrol_cli` **4.7.0**, both 2026-08-12, `sdk >=3.8.0` — so both
  install on the current local SDK. Also `patrol_finders` 3.6.0, `patrol_log` 0.10.1.
- **Web support:** added in `patrol_cli` **4.0.0** (Playwright/Chromium driven) and
  materially hardened since: 4.7.0 adds `patrol test --coverage` on web (same
  `coverage/patrol_lcov.info` as mobile, Chromium only), plus `--web-proxy`,
  `--web-storage-state`, `--web-bypass-csp`, `--web-trace`, and a fix for `-d chrome`
  failing on machines with no system Chrome.
- **Agent surface:** two things, both first-party:
  - **`patrol_mcp` 0.2.0** (pub, 2026-07-28, `sdk >=3.8.0`) — "An MCP server that empowers
    AI assistants to control, automate, and monitor interactive Patrol development
    sessions." Driven by `patrol develop`.
  - a **`patrol-setup` agent skill** at `leancodepl/patrol/skills/patrol-setup/SKILL.md`,
    which self-describes as **Android-only** for the initial wiring.
- **Install surface:** `flutter pub global activate patrol_cli` (needs PATH), dev_dependency,
  a `patrol:` block in `pubspec.yaml`, and native Android wiring. `patrol develop` +
  `patrol_mcp` is a long-lived local session, not a VM daemon.
- **Egress:** none inherent. Chromium is downloaded once at web-runner setup.
- **Fit: recommended add — the highest-value item on this list.** It is the only tool
  surveyed that covers **both** of this repo's targets (web *and* Android) with one test
  language, and the repo already has `integration_test` in `dev_dependencies` for exactly
  the paths Patrol is best at: the encrypted content store on real Keystore + real
  SQLCipher, and the T3 link ceremony with a real camera permission dialog. Cost is real
  and should be stated: `patrol_cli` must be on PATH (Windows), Android wiring is a
  one-time Gradle edit, and `**/test_bundle.dart` plus `.patrol.env` must be gitignored.
  Take the CLI and the web runner first; treat `patrol_mcp` as a later, separate decision
  (0.2.0, one month old, one maintainer-org — not something to make load-bearing yet).

### 1.7 `alchemist` — golden tests

- **What:** golden-file testing with platform-independent rendering, so goldens generated
  on Windows match goldens generated on CI Linux.
- **Provenance:** `Betterment/alchemist`, MIT, 300★. **v0.14.0, 2026-03-13** — and
  `pushed_at` is also **2026-03-13**: no commits in ~6 months, 40 open issues.
  `sdk >=3.8.0 <4.0.0`.
- **Install surface:** dev_dependency + `alchemist.yaml`. No daemon, no egress.
- **Fit: reject, with a caveat.** The problem alchemist solves is real for this repo
  (goldens authored on Windows 11, verified on CI Linux) and there is no maintained
  competitor — `golden_toolkit` is worse: latest 0.15.0 from **2023-02-21**, capped at
  `sdk <3.0.0`, i.e. it cannot resolve at all here. But 0.14.x with six months of silence
  is the wrong thing to make a CI gate depend on for a solo maintainer, and §1.5's
  Widget Previewer covers the *actual* need (eyeballing a widget across themes) without
  a golden-file corpus to re-baseline on every font or Material bump. If pixel regression
  becomes a felt problem, revisit; do not add it speculatively.

### 1.8 `maestro` (mobile.dev)

- **What:** declarative YAML device flows — `tapOn`, `inputText`, `assertVisible` — over
  Android, iOS and (Beta) desktop Chromium.
- **Provenance:** `mobile-dev-inc/maestro`, Apache-2.0, **15 595★** (by far the most
  popular thing in this document), `pushed_at` 2026-09-11, v2.10.0 on 2026-08-31.
  Kotlin/JVM. 513 open issues.
- **Install surface:** JVM CLI + managed Chromium download. Maestro Studio is a local
  inspector server. Maestro Cloud is a separate hosted product.
- **Egress:** none for local `maestro test`. Maestro Cloud uploads your app binary.
- **Fit: reject — popular, wrong tool here.** Three concrete reasons, all from Maestro's
  own docs. (1) Web is explicitly **Beta**, Chromium-only, with locale fixed to `en-US`
  and **"custom screen size and viewport configuration are currently preset"** — a
  responsive messenger cannot be verified on a fixed viewport. (2) For Flutter
  specifically the docs say elements "render differently" and you must add `Semantics`
  to make them addressable — i.e. Maestro's text-first selector model forces production
  widget changes to make tests work. (3) It duplicates Patrol, which is Flutter-native,
  already has a foothold in this repo, and needs no JVM. Choose one E2E tool; §1.6 wins.

### 1.9 DCM (`dcm.dev`)

- **What:** commercial Dart/Flutter static analysis — 536 rules at Pro, 22 metrics,
  unused-file/unused-localization detection, widget and image-asset analysis.
- **Provenance:** proprietary, closed-source. Current **1.39.0** (release article dated
  2026-08-24). Note the pub package named `dcm` is **unrelated** (`josercc/dcm`, last
  published 2024-05-17) — do not install it by mistake.
- **Install surface:** licensed CLI + IDE extensions. Pricing page lists an **MCP
  integration** row present on every tier including Free.
- **Egress:** license validation; unverified beyond that (closed source, no auditable
  claim available).
- **Fit: reject on the numbers.** DCM Free is **1 seat, 50 000 analyzed LOC**. This repo
  is **55 806 LOC in `frontend/lib` alone** — it does not fit the free tier. Pro is
  $16/month for 150k LOC. Paying a subscription, adding a closed-source binary with
  unauditable egress to a public E2EE repo, to get lint rules, when §1.4 gets most of the
  value for free and in-tree: no. Revisit only if `flutter_lints` + `very_good_analysis`
  prove insufficient in practice.

---

## 2. NestJS / TypeScript side

### 2.1 Official NestJS AI/MCP guidance — **the answer is "NestJS Observe", and it is a hosted SaaS**

`docs.nestjs.com` is a JS-rendered SPA, so the canonical text is the `llms.txt` index and
the markdown in `nestjs/docs.nestjs.com`. Searching both: there is **no** NestJS chapter
on writing agent rules, no official Nest skills repo, and no `@nestjs/mcp` package
(npm returns 404). The only official MCP surface is inside the new observability product.

- **What:** `@nestjs/observe` is a first-party auto-instrumenting APM that hooks Nest's
  request lifecycle via the `instrument` option of `NestFactory.create()` (available since
  `@nestjs/core` v11.1.4). **NestJS Observe** is the hosted dashboard, and it exposes a
  **read-only MCP server** over Streamable HTTP at `POST https://<host>/mcp` with tools
  `find_regressions`, `list_slow_operations`, `get_operation_details`, `get_trace`,
  `get_trace_logs`, `list_error_groups`, `get_error_details`, `get_affected_users`,
  `list_jobs`, `list_slos`, `list_alert_rules`, etc.
- **Provenance:** `@nestjs/observe` **0.1.8**, MIT, published 2026-08-27; package first
  created 2026-08-21 — **three weeks old**. Peers `@nestjs/common`/`core`
  `^11.0.0 || ^12.0.0`, so it is installable on this repo's Nest 11.
- **Install surface:** npm SDK in-process on the VM + `claude mcp add observe --transport
  http … --header "Authorization: Bearer <token>"`. MCP tokens are minted in the dashboard,
  shown once, never expire unless you set an expiry, and **act as the user who created
  them** with that user's full project permissions.
- **Egress: substantial.** Telemetry ships to `https://observe-api.nestjs.com` by default
  (`endpoint` / `OBSERVE_ENDPOINT` can be repointed at "a local or self-hosted collector",
  but no self-hosted collector product is documented). What leaves: routes, class/method
  names, stack traces with **source lines around the failing frame**, per-user activity
  when a user id is reported, and — if `forwardLogs` is on — log lines (redacted by
  default for bearer tokens, JWTs, PEM keys, `key=value` secrets, card numbers).
- **Fit: reject.** Four independent blockers. (1) **The MCP server is a higher-tier paid
  feature** — the overview lists it, alongside SLOs and SSO, under "on the higher tiers",
  not on the free tier. (2) **Egress**: an E2EE messenger shipping stack frames with
  source context and per-end-user activity to a third party is the wrong default, and
  redaction is a regex denylist, not a guarantee. (3) **The 4 GB VM**: this is an
  in-process agent doing `runtimeMetrics` sampling every 60 s plus CPU profiles, on the
  box that also runs Postgres 16 — same class of objection that killed self-hosted Sentry
  in the July audit (16 GB), smaller in degree. (4) It is **0.1.8, three weeks old**.
  Revisit in six months if a self-hostable collector ships and the MCP tier changes.

### 2.2 NestJS 12 — the blocker still holds, one detail changed

- **Provenance:** `@nestjs/{core,common,platform-*,websockets,testing}` **12.0.1**, MIT,
  published 2026-08-27. `@nestjs/schematics` 12.0.1 (2026-09-11).
  `@nestjs/devtools-integration` 12.0.0 peers `@nestjs/common: ^12.0.0` **exactly**.
- **Fit: stay on 11 — `dependabot.yml:28-38` is still correct.** The recorded reason
  (`@nestjs/throttler` 6.5.0 peers only up to `^11`, so Nest 12 breaks the
  `WsThrottlerGuard` rate-limit contract) is unchanged. Re-check trigger is unchanged:
  a `@nestjs/throttler` release peering `^12`. Additional datum for when that lands:
  `@nestjs/devtools-integration` has already cut a 12.0.0 with a hard `^12` peer, so the
  family move is a single-PR, all-or-nothing operation exactly as the comment says.

### 2.3 Vitest vs Jest — **NestJS's own docs now default to Vitest**

- **Primary evidence**, `nestjs/docs.nestjs.com/content/fundamentals/unit-testing.md`:
  the CLI "provides integration with **Vitest** and Supertest", and
  *"**Newly generated projects use Vitest by default.** The testing APIs exposed by Nest
  do not depend on a specific runner, so the same patterns work with other tools as well."*
- **Provenance:** `vitest` **5.0.0**, MIT, 2026-09-03 (17 093★, `pushed_at` 2026-09-11).
  `jest` **30.5.1**, MIT, 2026-09-01 (45 460★, `pushed_at` 2026-09-10). Both healthy.
- **Repo state:** `jest ^30.4.2` + `ts-jest ^29.4.12`, config split across
  `jest.config.json` and an inline `jest` block in `package.json:89-105`.
- **Fit: explicitly not — do not migrate.** Nest's default changed; Nest's *support* did
  not. The docs are explicit that the testing APIs are runner-agnostic, which means the
  upside of switching is faster runs, not correctness. Against that: Jest 30 is actively
  maintained, the suite is 38 893 LOC of already-working tests, and a runner migration on
  a solo-maintained crypto backend is pure risk for zero behavioural gain. Take Vitest
  only if Jest run time becomes an actual bottleneck — and then as a deliberate project,
  not a dependency bump. Worth fixing independently: the **duplicated Jest config**
  (`jest.config.json` *and* the `package.json` `jest` block) is a real latent trap.

### 2.4 `knip`

- **What:** finds unused files, dependencies, and exports across a JS/TS project.
- **Provenance:** `webpro-nl/knip`, **ISC**, 12 248★, `pushed_at` 2026-09-11.
  **6.35.1**, published 2026-09-09. Ships **183 plugins**, including a first-class
  **Nest** plugin plus **Jest**, **Vitest**, **ESLint**, **Prettier**, **ts-node**,
  **dotenv** and **GitHub Actions** plugins.
- **Install surface:** single dev_dependency, `npx knip`. No daemon, no egress.
- **Fit: recommended add — best value-per-byte on the backend.** The Nest plugin matters
  specifically because Nest's DI makes providers look unreferenced to a naive analyser:
  a generic unused-export tool reports a controller registered only in a module's
  `providers` array as dead code. Knip understands the Nest entry points, so its output
  is actionable rather than noise. For a solo maintainer on a codebase that has already
  done cutovers (graphify removed, `@types/node` pinned), a tool that names orphaned
  files and dependencies *precisely* is the cheapest cleanup lever available. Start with
  `--include files,dependencies` and let exports follow once the first pass is clean.

### 2.5 `dependency-cruiser`

- **What:** validates and visualises module dependencies against rules you write
  (e.g. "nothing in `auth/` may import from `media/`").
- **Provenance:** `sverweij/dependency-cruiser`, MIT, 7 163★, `pushed_at` 2026-09-11.
  **18.2.0**, published 2026-08-10. Knip ships a `dependency-cruiser` plugin, so the two
  compose rather than compete.
- **Install surface:** dev_dependency + `.dependency-cruiser.js`. Graph output wants
  Graphviz `dot` for SVG; the JSON/text reporters do not. No daemon, no egress.
- **Fit: optional, second in line behind knip.** The genuine use here is one enforceable
  architectural invariant on an E2EE backend — e.g. no module outside the crypto boundary
  may import the key-handling internals — which is the kind of rule that review misses
  and a CI check does not. But it is a rules file you must *write and maintain*; empty,
  it finds nothing. Add it when there is a specific boundary worth pinning, not before.
  Note also this replaces the niche graphify occupied (removed 2026-09-10 for 1.8% Dart
  edge precision) — and unlike graphify it is TypeScript-only, which is precisely why its
  precision is not in question.

### 2.6 `typescript-eslint` v8 — and why **TypeScript 7 is a trap**

- **Provenance:** `typescript-eslint`, MIT, 16 387★, `pushed_at` 2026-09-11.
  **8.70.0**, published 2026-09-07. Repo is on `^8.65.0` — five minors behind, same major.
- **The decisive datum:** `@typescript-eslint/{eslint-plugin,parser}` 8.70.0 declare
  `peerDependencies.typescript: ">=4.8.4 <6.1.0"` and
  `eslint: "^8.57.0 || ^9.0.0 || ^10.0.0"`.
  Meanwhile npm `typescript` `latest` is **7.0.2** (2026-07-08, **Apache-2.0** — the
  native port), with `6.0.0-beta` and `7.1.0-dev` tags alive.
- **Fit: keep typescript-eslint 8.x, keep TypeScript 5.7, do not chase TS 7.**
  `<6.1.0` means TypeScript 7 is **outside** typescript-eslint's supported range —
  adopting TS 7 today would silently strand every type-aware lint rule the backend runs
  (`eslint ^10.8.0` + `typescript-eslint ^8.65.0`, `backend/package.json:69,82`). The
  project also documents that it mirrors DefinitelyTyped's 2-year support window, so the
  upper bound is policy, not oversight. Routine `^8.65 → ^8.70` bumps are fine and already
  covered by the `backend-minor-patch` Dependabot group. **Add a TS major guard to
  `dependabot.yml`** on the same pattern as the existing `@nestjs/*` and `@types/node`
  rules — otherwise a `typescript` 5 → 7 major PR will eventually land and break linting
  in a way that looks like an ESLint bug.

### 2.7 `artillery` vs `k6` for Socket.IO load testing — **not close**

This repo's realtime path is Socket.IO on both ends (`@nestjs/platform-socket.io` ⇄
`socket_io_client`). Socket.IO is *not* raw WebSocket: it layers Engine.IO framing,
namespaces, acknowledgements and a polling→websocket upgrade on top.

| | artillery | k6 |
| --- | --- | --- |
| Provenance | `artilleryio/artillery`, **MPL-2.0**, 9 075★, `pushed_at` 2026-08-26; npm **2.0.34** (2026-08-14) | `grafana/k6`, **AGPL-3.0**, 31 449★, `pushed_at` 2026-09-11; **v2.2.0** (2026-08-10) |
| Socket.IO | **built-in `socketio` engine** | **none** |
| Evidence | Docs document `engine: socketio` with `emit` (array or `channel`/`data`), `response` validation via `channel`/`on`/`args`/`match` JSONPath, `acknowledge` for Socket.IO acks, `namespace`, `transports: ['websocket']`, `extraHeaders`, and mixing HTTP actions in the same scenario | Docs cover only `k6/websockets` (WHATWG standard) and legacy `k6/ws`; recommend `k6/websockets` for new tests. Every Socket.IO issue in `grafana/k6` is **closed**, incl. the canonical "Add support for socket.io" **#1306, opened 2020-01-10, closed 2024-02-12** |
| Install | npm dev_dependency | single Go binary |
| Egress | none for local runs; Artillery Cloud + the bundled AWS/Azure distributed-load deps are opt-in | none |

- **Fit: artillery, recommended — and run it *from the dev PC against* the VM, never on it.**
  Artillery's engine speaks acks and namespaces, which is what actually needs testing here
  (does a ratchet-key delivery ack under concurrency?). With k6 you would hand-roll
  Engine.IO framing in JS and then be load-testing your own test harness. The one real
  caveat: artillery 2.x pulls a large dependency tree (`@aws-sdk/*`, `@azure/*`,
  `@opentelemetry/*`) for its distributed-load features. Install it in `scripts/smoke/`
  (which already exists as a separate `package.json`), **not** in `backend/`, so the
  production image and `backend/package-lock.json` stay clean. **VM warning:** a load
  generator must not share the 4 GB box with the Postgres instance it is hammering, or
  you measure contention instead of the server.

---

## 3. Cross-cutting

### 3.1 `pg_stat_statements` — in-core, and the cheapest observability on offer

- **Provenance:** PostgreSQL 16 contrib module; PostgreSQL Licence; versioned with the
  server, so "maintained" is the Postgres release cycle itself.
- **Install surface:** must be listed in `shared_preload_libraries` (**requires a server
  restart**), then `CREATE EXTENSION pg_stat_statements`.
- **Egress:** none. Stays in the database.
- **4 GB VM impact — quantified from the docs:** "requires additional shared memory
  proportional to `pg_stat_statements.max`", and *"this memory is consumed whenever the
  module is loaded, even if [it is not active]"*. Query **texts** are held in an external
  disk file, not shared memory, so long queries are cheap in RAM but the file can grow.
- **Fit: recommended add — the single best VM-side change here.** It answers "which query
  is slow" with bounded, tunable, fixed-at-startup memory on a box where every other
  observability option (§2.1, self-hosted Sentry) was rejected for footprint. Set
  `pg_stat_statements.max` conservatively rather than accepting the default, and consider
  `track_utility = off`. It is a restart, so fold it into a planned deploy window.

### 3.2 `pgbadger`

- **What:** Perl log analyser that turns Postgres logs into HTML reports.
- **Provenance:** `darold/pgbadger`, PostgreSQL Licence, 4 060★, `pushed_at` 2026-07-14.
  Latest release **13.2, 2025-12-29** — over eight months old, though the project is
  clearly still alive.
- **Install surface:** Perl script. Runs **offline over log files**; no daemon.
- **Egress:** none.
- **Fit: optional, and strictly worse than §3.1 for this box.** It needs verbose
  `log_min_duration_statement` logging to be useful, which costs disk I/O on the VM
  continuously, and then a Perl toolchain to read it. `pg_stat_statements` answers the
  same question live with no log volume. Keep pgbadger in reserve for a one-off forensic
  pass over an incident's logs — pull the logs to the dev PC and run it there.

### 3.3 `pgroll` vs `reshape` — zero-downtime migrations

| | pgroll | reshape |
| --- | --- | --- |
| Provenance | `xataio/pgroll`, Apache-2.0, 6 575★, `pushed_at` 2026-09-08, **v0.16.3** (2026-09-08) | `fabianlindfors/reshape`, MIT, 1 849★, `pushed_at` 2026-09-09, **0.11.2** (2026-09-09) |
| Language | Go (single binary) | Rust (single binary) |
| Model | serves **multiple schema versions simultaneously** via versioned views; two-phase `start`/`complete` | keeps old and new schema available at once; Postgres 12+ |
| Agent angle | — | ships **`reshape docs`**, explicitly "designed to be used with coding agents", with a suggested system-prompt line |
| Install | CLI + a connection to the DB. No daemon. | same |
| Egress | none | none |

- **Fit: explicitly not, both.** This is genuinely interesting tech and a clean no. The
  repo migrates with **TypeORM** (`typeorm ^1.1.0`), and both tools require the
  *application* to cooperate with two live schema versions during a rollout — you adopt a
  migration *architecture*, not a CLI. A solo maintainer deploying a single backend
  container to one VPS does not have the rolling-deploy topology that zero-downtime
  expand/contract exists to serve; a brief maintenance window costs nothing here and is
  already the deploy shape. Adding a second, non-TypeORM source of schema truth to an
  E2EE app whose encrypted-content paths are the riskiest thing in the codebase is a net
  loss. `reshape docs` is a genuinely good agent-integration pattern worth stealing
  conceptually — a CLI subcommand that emits its own docs for an agent — without taking
  the tool.

### 3.4 `docker scout` vs `trivy` — trivy stays

- **trivy:** `aquasecurity/trivy`, Apache-2.0, 37 873★, `pushed_at` 2026-09-11,
  **v0.74.0** (2026-08-14). Single Go binary, local vulnerability DB, no account.
  **Already installed** (July audit). No material change: still actively released.
- **docker scout:** `docker/scout-cli`, **license NOASSERTION** (not an OSI licence
  GitHub can identify), **452★**, `pushed_at` 2026-09-11, v1.24.0 (2026-07-30).
- **Egress, from Docker's own quickstart:** you must be "signed in to your Docker account,
  either by running the `docker login` command", then `docker scout enroll <ORG_NAME>`
  and `docker scout repo enable`. Analysis output includes the line
  **`✓ Image stored for indexing`**, and results land in the hosted
  **Docker Scout Dashboard** at `scout.docker.com`. Policy evaluation requires
  `docker scout config organization <ORG_NAME>`.
- **Fit: reject docker scout, keep trivy.** Scout requires a Docker account, an org
  enrolment, and uploads the image index to Docker's cloud to do what trivy does locally
  with no account and no egress. For a public-repo E2EE project with a solo maintainer,
  "same answer, plus an account and an upload" is a strict downgrade. The only thing Scout
  adds is base-image currency advice — and its own docs point at Dependabot
  `package-ecosystem: "docker"` for that, which is free and already the repo's mechanism.

### 3.5 Renovate vs Dependabot for a pub + npm monorepo — **Renovate genuinely fixes the recorded bug**

The repo's `dependabot.yml:45-55` documents a specific, reproduced failure: a pub group
with no explicit `patterns` **did not honour the update-config-level `ignore` list**
(#157, #169, #171 each bundled `drift`/`drift_dev`/`sqlite3` against standing rules), and
every resulting PR was unmergeable because `flutter pub get` could not resolve the set.
The recorded workaround was to delete `groups:` entirely and accept up to 3 PRs/month.

Renovate addresses both halves of that failure, and the evidence is in its source and docs:

1. **Exclusion is a first-class rule, not a group modifier.** `ignoreDeps` is documented
   as being *identical to* a package rule with `"enabled": false`:
   ```json
   { "packageRules": [ { "matchPackageNames": ["drift", "drift_dev", "sqlite3"], "enabled": false } ] }
   ```
   A disabled dependency is removed from the update set before branching, so it **cannot**
   reappear inside a group. `groupName` is orthogonal — "free text [with no] semantic
   interpretation… All updates sharing the same `groupName` will be placed into the same
   branch/PR" — which is exactly the separation of concerns Dependabot's `groups:` lacks.
2. **Renovate actually resolves the lockfile.** `lib/modules/manager/pub/index.ts` exports
   `updateArtifacts`, `supportsLockFileMaintenance = true`, and
   `lockFileNames = ['pubspec.lock']`. `artifacts.ts` detects `sdk: flutter` in the
   pubspec, picks `flutter` over `dart`, reads the SDK constraint out of `pubspec.lock`,
   and runs `flutter pub upgrade <deps>` (or `flutter pub get --no-precompile`) under a
   tool constraint — logging `Failed to update lock file` on failure. So an unresolvable
   set surfaces as an artifact error on the branch instead of a clean-looking, dead PR.
3. **It can bump the Flutter/Dart SDK pin too.** `supportedDatasources` includes
   `DartVersionDatasource` and `FlutterVersionDatasource` — directly relevant to §0's
   3.44-vs-3.47 drift.
4. `minimumGroupSize` lets you say "only open the grouped PR when N updates are ready",
   which is the knob that would have prevented the partial-group churn.

- **Provenance:** `renovatebot/renovate`, **AGPL-3.0**, 22 469★, `pushed_at` 2026-09-12,
  npm **44.82.1** published 2026-09-12 (multiple releases *per day*).
  Note the docs banner: "Renovate 44 was accidentally released as a major version, even
  though the changes were non-breaking."
  Dependabot for comparison: `dependabot/dependabot-core`, MIT, 5 765★, 1 533 open issues.
- **Install surface:** the hosted Mend GitHub App, or self-hosted CLI in Actions. The
  self-hosted CLI on this VM is a poor fit — it needs the Flutter *and* Node toolchains
  present to run `updateArtifacts`.
- **Egress:** hosted app reads the repo (already public) and queries pub.dev/npm for
  versions. Self-hosted: the same registry queries from wherever it runs.
- **Fit: recommended — migrate, using the hosted app, and only after the pub grouping is
  proven on a branch.** This is the one place where switching tools solves a documented,
  reproduced, currently-worked-around defect rather than adding capability. Two honest
  caveats: (a) Renovate is AGPL-3.0 and ships many releases a day, so pin the Action/app
  and do not track `latest` blindly; (b) the whole reason to switch is grouping, so the
  migration is only worth it if the first grouped pub PR resolves — verify that before
  deleting `dependabot.yml`. Keep Dependabot **security** alerts regardless: those are a
  repo-settings feature, independent of either tool's version-update config, and the
  existing `ignore` entries are carefully scoped to `version-update:*` precisely so CVE
  fixes still open PRs.

### 3.6 The official MCP registry, checked

`registry.modelcontextprotocol.io/v0/servers?search=…` (`modelcontextprotocol/registry`,
7 239★, `pushed_at` 2026-09-09) was searched for `postgres`, `flutter`, `dart`, `nestjs`,
`socket`, `load test`, `typescript`. Result, stated plainly:

- **`nestjs` → 0 results. `load test` → 0 results.**
- `postgres` → 8 results, **all** from one publisher (`ai.getvda/*`), all version 1.0.0,
  all docker-compose "stack generators" — none is a Postgres query/introspection server.
- `flutter` → third-party only (`flutter-mcp-toolkit`, `flutter_structure_mcp`,
  `flutter-skill`); the **official** Dart/Flutter MCP server is *not* in the registry
  because it ships inside the Dart SDK (§1.1).
- `dart` → keyword collisions (`dartai`, `calendartools`, `digitaldarts/seo-expert`).
- `typescript` → boilerplates and AST toys.

- **Fit conclusion:** the registry currently offers **nothing** for this stack. It also
  confirms the July audit's Postgres decision by a different route: the archived reference
  Postgres MCP has no maintained successor in the official registry, so there is still
  nothing to reconsider. Treat the registry as a namespace/verification service, not a
  discovery channel — and keep sourcing MCP servers from the vendor that owns the tool
  (Dart SDK, Patrol, NestJS), which is the pattern every credible entry in this document
  follows.

---

## Recommended adds

Ordered by value per unit of risk. Nothing here needs a daemon on the 4 GB VM except
§3.1, which is a restart plus bounded shared memory.

1. **`pg_stat_statements`** (§3.1) — in-core, zero egress, answers "which query is slow"
   on a box where every hosted APM was rejected. Set `max` explicitly; needs a restart.
2. **`knip`** (§2.4) — ISC, one dev_dependency, first-class **Nest** plugin so DI-registered
   providers aren't false-positived. Best cleanup lever on the backend.
3. **Flutter 3.47 + Widget Previewer** (§1.5) — Previewer went stable in 3.47; turns
   "boot the web app and navigate" into one annotated builder an agent can render across
   themes. Also unblocks §1.4. Gitignore `.widget_preview/`.
4. **`patrol` CLI + web runner** (§1.6) — Apache-2.0, `sdk >=3.8.0` so it installs today;
   the only tool covering **both** web and Android, which is exactly this repo's shape.
   Gitignore `**/test_bundle.dart` and `.patrol.env`. Defer `patrol_mcp` (0.2.0).
5. **Renovate, hosted app** (§3.5) — the only item that fixes a *documented* current
   defect: `enabled:false` package rules are evaluated before grouping, and the pub manager
   really runs `flutter pub upgrade` so unresolvable sets fail loudly. Prove one grouped
   pub PR resolves before deleting `dependabot.yml`.
6. **`very_good_analysis` 10.3.0 now / 11.0.0 after the Flutter bump** (§1.4) —
   v11 needs Dart ^3.13.0, which CI has and the dev box does not. Sequence it.
7. **`flutter/agent-plugins` skills via `npx skills`** (§1.2) — harness-neutral files on
   disk. Hand-pick rules; `CLAUDE.md` stays authoritative over generic Flutter idiom.
8. **`artillery` in `scripts/smoke/`** (§2.7) — the only tool with a real Socket.IO engine
   (acks, namespaces). Keep it out of `backend/`; run it *at* the VM, never *on* it.
9. **A `typescript` semver-major ignore in `dependabot.yml`** (§2.6) — TS 7.0.2 is out and
   typescript-eslint 8.70.0 peers `<6.1.0`. Guard it like `@nestjs/*` and `@types/node`.

**Optional, on a trigger:** `dependency-cruiser` (§2.5) once there is a specific crypto-boundary
invariant worth enforcing; `pgbadger` (§3.2) for one-off incident forensics, run on the dev PC.

## Explicitly not

| Tool | Why not |
| --- | --- |
| **NestJS Observe MCP** (§2.1) | MCP is a **higher-tier paid** feature; ships stack frames with source context and per-end-user activity to `observe-api.nestjs.com`; in-process APM + CPU profiles on the 4 GB VM next to Postgres; `@nestjs/observe` is **0.1.8, three weeks old**. |
| **Developer Knowledge MCP** (§1.3) | Hosted; every query egresses to Google. `read` on docs.flutter.dev's `.md` alternates already does this locally — that is how this document was researched. |
| **`maestro`** (§1.8) | Most-starred tool here (15.6k) and still wrong: web is **Beta**, Chromium-only, **viewport preset** (fatal for a responsive messenger), demands production `Semantics` edits for Flutter, needs a JVM, and duplicates Patrol. |
| **DCM** (§1.9) | Free tier is 50k LOC; `frontend/lib` alone is **55 806**. Pro is $16/mo for closed-source, unauditable-egress lint rules on a public E2EE repo. |
| **`docker scout`** (§3.4) | Requires `docker login` + `scout enroll` and **uploads the image index** ("Image stored for indexing") to `scout.docker.com`. `trivy` v0.74.0 gives the same answer locally, no account. License is NOASSERTION. |
| **`pgroll` / `reshape`** (§3.3) | Both excellent, both an *architecture*: the app must serve two live schema versions. Repo migrates with TypeORM and deploys one container to one VPS — a maintenance window is free here. Steal `reshape docs`' agent pattern, not the tool. |
| **Vitest migration** (§2.3) | Nest's *default* changed; its *support* did not — the docs call the testing APIs runner-agnostic. Jest 30.5.1 is healthy. Zero behavioural gain, real risk across 38 893 LOC of tests. (Do fix the duplicated Jest config.) |
| **NestJS 12** (§2.2) | `@nestjs/throttler` 6.5.0 still peers `^11` max → breaks `WsThrottlerGuard`. Unchanged since July. `@nestjs/devtools-integration` 12.0.0's hard `^12` peer confirms it must be one all-or-nothing PR. |
| **TypeScript 7** (§2.6) | `typescript-eslint` 8.70.0 peers `typescript: ">=4.8.4 <6.1.0"`. Adopting TS 7 silently strands every type-aware lint rule. |
| **`k6` for Socket.IO** (§2.7) | No Socket.IO engine, ever. Issue #1306 ("Add support for socket.io") opened 2020-01-10, **closed 2024-02-12**; all six Socket.IO issues closed. You'd hand-roll Engine.IO framing. |
| **`alchemist`** (§1.7) | v0.14.0 and `pushed_at` both **2026-03-13** — ~6 months silent, 40 open issues. Wrong dependency for a solo-maintained CI gate; Widget Previewer covers the real need. (`golden_toolkit` is worse: 2023-02-21, `sdk <3.0.0`, cannot resolve.) |
| **MCP registry servers** (§3.6) | `nestjs` → 0 hits. `postgres` → 8 hits, all one publisher, all compose-file generators. Nothing usable for this stack; source MCP from the tool's own vendor instead. |

### Windows / VM constraints touched

- `hub start` cannot spawn `.bat` directly — relevant to `patrol_cli`, which is installed
  via `flutter pub global activate` and must be on PATH. Invoke the real executable.
- No recommended add requires a new long-running VM daemon. `pg_stat_statements` (§3.1) is
  the only VM-side change: `shared_preload_libraries` + restart + bounded shared memory
  proportional to `pg_stat_statements.max`.
- Rejected specifically for the 4 GB box: NestJS Observe in-process APM (§2.1), and
  running `artillery` on the VM rather than against it (§2.7).

---

## Sources

Every URL below was read for this document.

**Flutter / Dart**
- https://docs.flutter.dev/ai
- https://docs.flutter.dev/ai/get-started
- https://docs.flutter.dev/ai/tools
- https://docs.flutter.dev/tools/widget-previewer
- https://raw.githubusercontent.com/flutter/website/main/sites/docs/src/content/release/whats-new.md
- https://raw.githubusercontent.com/flutter/website/main/sites/docs/src/content/release/release-notes/release-notes-3.47.0.md
- https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json
- https://api.github.com/repos/flutter/flutter
- https://api.github.com/repos/flutter/agent-plugins
- https://api.github.com/repos/dart-lang/skills
- https://api.github.com/repos/dart-lang/ai
- https://pub.dev/packages/dart_mcp_server
- https://pub.dev/api/packages/dart_mcp_server
- https://pub.dev/api/packages/dart_mcp
- https://pub.dev/api/packages/skills
- https://pub.dev/api/packages/very_good_analysis
- https://pub.dev/api/packages/alchemist
- https://pub.dev/api/packages/golden_toolkit
- https://pub.dev/api/packages/dcm
- https://api.github.com/repos/VeryGoodOpenSource/very_good_analysis
- https://raw.githubusercontent.com/VeryGoodOpenSource/very_good_analysis/main/CHANGELOG.md
- https://github.com/VeryGoodOpenSource/very_good_analysis/releases.atom
- https://api.github.com/repos/Betterment/alchemist
- https://github.com/Betterment/alchemist/releases.atom
- https://dcm.dev/pricing/

**Patrol / Maestro**
- https://api.github.com/repos/leancodepl/patrol
- https://patrol.leancode.co/documentation
- https://raw.githubusercontent.com/leancodepl/patrol/master/packages/patrol_cli/CHANGELOG.md
- https://raw.githubusercontent.com/leancodepl/patrol/master/skills/patrol-setup/SKILL.md
- https://pub.dev/api/packages/patrol
- https://pub.dev/api/packages/patrol_cli
- https://pub.dev/api/packages/patrol_mcp
- https://pub.dev/api/packages/patrol_log
- https://pub.dev/api/packages/patrol_finders
- https://docs.maestro.dev/get-started/supported-platform/web-browser
- https://github.com/mobile-dev-inc/maestro/releases.atom

**NestJS / TypeScript**
- https://docs.nestjs.com/llms.txt
- https://raw.githubusercontent.com/nestjs/docs.nestjs.com/master/content/observability/mcp-server.md
- https://raw.githubusercontent.com/nestjs/docs.nestjs.com/master/content/observability/overview.md
- https://raw.githubusercontent.com/nestjs/docs.nestjs.com/master/content/observability/sdk.md
- https://raw.githubusercontent.com/nestjs/docs.nestjs.com/master/content/fundamentals/unit-testing.md
- https://registry.npmjs.org/@nestjs/core
- https://registry.npmjs.org/@nestjs/observe
- https://registry.npmjs.org/@nestjs/devtools-integration
- https://registry.npmjs.org/@nestjs/platform-socket.io
- https://registry.npmjs.org/@nestjs/websockets
- https://registry.npmjs.org/@nestjs/schematics
- https://registry.npmjs.org/typescript
- https://registry.npmjs.org/eslint
- https://registry.npmjs.org/vitest
- https://registry.npmjs.org/jest
- https://registry.npmjs.org/@typescript-eslint/eslint-plugin
- https://registry.npmjs.org/@typescript-eslint/parser
- https://registry.npmjs.org/typescript-eslint
- https://raw.githubusercontent.com/typescript-eslint/typescript-eslint/main/docs/users/Dependency_Versions.mdx
- https://github.com/typescript-eslint/typescript-eslint/releases.atom
- https://api.github.com/repos/nestjs/nest

**Unused code / architecture**
- https://knip.dev/reference/plugins
- https://registry.npmjs.org/knip
- https://github.com/webpro-nl/knip/releases.atom
- https://api.github.com/repos/webpro-nl/knip
- https://registry.npmjs.org/dependency-cruiser
- https://github.com/sverweij/dependency-cruiser/releases.atom
- https://api.github.com/repos/sverweij/dependency-cruiser

**Load testing**
- https://www.artillery.io/docs/reference/engines/socketio
- https://registry.npmjs.org/artillery
- https://api.github.com/repos/artilleryio/artillery
- https://grafana.com/docs/k6/latest/using-k6/protocols/websockets/
- https://api.github.com/repos/grafana/k6
- https://github.com/grafana/k6/releases.atom
- https://api.github.com/search/issues?q=repo:grafana/k6+socket.io+in:title

**Postgres**
- https://www.postgresql.org/docs/16/pgstatstatements.html
- https://raw.githubusercontent.com/xataio/pgroll/main/README.md
- https://github.com/xataio/pgroll/releases.atom
- https://api.github.com/repos/xataio/pgroll
- https://raw.githubusercontent.com/fabianlindfors/reshape/master/README.md
- https://github.com/fabianlindfors/reshape/releases.atom
- https://api.github.com/repos/fabianlindfors/reshape
- https://github.com/darold/pgbadger/releases.atom
- https://api.github.com/repos/darold/pgbadger

**Supply chain / dependency automation**
- https://docs.docker.com/scout/quickstart/
- https://api.github.com/repos/docker/scout-cli
- https://github.com/docker/scout-cli/releases.atom
- https://api.github.com/repos/aquasecurity/trivy
- https://github.com/aquasecurity/trivy/releases.atom
- https://github.com/gitleaks/gitleaks/releases.atom
- https://github.com/google/osv-scanner/releases.atom
- https://docs.renovatebot.com/modules/manager/pub/
- https://raw.githubusercontent.com/renovatebot/renovate/main/lib/modules/manager/pub/index.ts
- https://raw.githubusercontent.com/renovatebot/renovate/main/lib/modules/manager/pub/artifacts.ts
- https://raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/configuration-options.md
- https://registry.npmjs.org/renovate
- https://github.com/renovatebot/renovate/releases.atom
- https://api.github.com/repos/renovatebot/renovate
- https://api.github.com/repos/dependabot/dependabot-core

**MCP registry**
- https://registry.modelcontextprotocol.io/v0/servers?search=postgres
- https://registry.modelcontextprotocol.io/v0/servers?search=flutter
- https://registry.modelcontextprotocol.io/v0/servers?search=dart
- https://registry.modelcontextprotocol.io/v0/servers?search=nestjs
- https://registry.modelcontextprotocol.io/v0/servers?search=socket
- https://registry.modelcontextprotocol.io/v0/servers?search=load+test
- https://registry.modelcontextprotocol.io/v0/servers?search=typescript
- https://api.github.com/repos/modelcontextprotocol/registry
- https://api.github.com/repos/anthropics/claude-plugins-official
