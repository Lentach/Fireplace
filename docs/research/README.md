# Agent-tooling research (2026-09)

Four files, one question each, **primary sources only** (vendor docs, repo APIs, the harness's own `omp://` docs). Every entry carries provenance (owner, license, stars, `pushed_at`, release + date), install surface, egress, and a fit verdict argued against THIS stack. Popularity is not a recommendation; several very popular tools are rejected on fit with the reason stated.

| File | Question | Headline |
|---|---|---|
| `2026-09-agent-harness-practice.md` | Do our instruction files match what the vendors say, and does OMP actually load them? | **OMP injects only `AGENTS.md`** (it shadows root `CLAUDE.md` at depth 0); comma-string `globs` are inert in OMP; `.omp/rules` + `condition:` file globs is the mechanism that fires at edit time and reaches subagents. 11 ranked fixes — 7 applied 2026-09-10. |
| `2026-09-mcp-servers.md` | Which MCP servers are worth mounting? | **Still one** (Dart MCP). 46 verified. Postgres: `docker exec psql` wins. `chrome-devtools-mcp`: ad-hoc only (58 schemas, telemetry on). Nothing for NestJS/Jest exists. MCP spec went stateless 2026-07-28. |
| `2026-09-skills-and-plugins.md` | Which skills/plugins, and does OMP honour Claude Code hooks? | **OMP does not run Claude Code hooks** (every hooks-based plugin is inert here). Only credible Dart collection: `kevmoo/dash_skills`. Two on-disk skills are behind upstream (`diagnosing-bugs` lost a redaction section). Nothing matches `umbra-session-end`. |
| `2026-09-flutter-nest-agent-tooling.md` | Stack-specific tooling worth adding? | **CI/local SDK split exists** (CI floats to Dart 3.13, box is 3.12). Flutter 3.47 = Widget Previewer stable. `patrol` covers web+Android. `artillery` speaks Socket.IO, k6 never will. Renovate fixes the recorded Dependabot pub-grouping bug. NestJS Observe MCP: paid tier + egress → reject. |

Recommended adds are sequenced in `docs/agents/workflow-2.0.md` §7 "Batch 8".
