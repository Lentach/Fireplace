# Agent tooling cleanup — MCP dedup, node_repl/generate_image disable, Dart+TS language servers

**Date:** 2026-07-08

## What was done

Machine-local agent-harness (OMP) tooling cleanup — **zero app code touched** (another agent was active on this branch; only untracked/local config changed).

1. **context7 MCP deduplicated.** It was mounted twice: once from `~/.omp/agent/mcp.json` and once discovered from the Claude plugin `context7@claude-plugins-official` (`~/.claude/plugins/...`). Removed the entry from `~/.omp/agent/mcp.json`; the plugin copy is now the single source. `.claude`/`.codex` configs untouched (Claude Code / Codex unaffected).
2. **node_repl MCP disabled for OMP.** Source: `~/.codex/config.toml` `[mcp_servers.node_repl]` (OpenAI Codex runtime), picked up by OMP's Codex discovery. Fully redundant with OMP's built-in `eval` (JS/Python kernels) + `browser`. Suppressed via `"disabledServers": ["node_repl"]` in `~/.omp/agent/mcp.json` — the documented mechanism that does not edit Codex's own config.
3. **generate_image call-blocked.** No `<tool>.enabled` key exists for it (SDK-injected custom tool, unlike `web_search.enabled`/`browser.enabled`). Applied the only available lever: `omp config set tools.approval '{"generate_image":"deny"}'`. Caveat: this denies invocation but likely does NOT unmount the schema from the prompt, so token savings are ~0; true unmount would be an upstream OMP feature.
4. **Dart + TypeScript language servers wired** (was: "No language servers configured"):
   - Installed `typescript-language-server@5.3.0` + `typescript` globally (npm).
   - `dart` 3.11.5 already on PATH via Flutter SDK.
   - Auto-detection could not fire because the repo root has no `package.json`/`tsconfig.json`/`pubspec.yaml` (they live in `backend/` and `frontend/`). Added project override `.omp/lsp.json` with `rootMarkers: [".git", ...]` for both servers.
   - Added `.omp/` to `.git/info/exclude` (local-only) so the config never shows in `git status` for other agents.

## Key files

- `~/.omp/agent/mcp.json` — context7 entry removed; `disabledServers: ["node_repl"]` added
- `~/.omp/agent/config.yml` — `tools.approval: {"generate_image":"deny"}` (via `omp config set`)
- `.omp/lsp.json` (repo, untracked + locally excluded) — rootMarker overrides for `typescript-language-server` and `dartls`
- `.git/info/exclude` — `.omp/` line appended

## Verification

- `lsp reload *` → `Reloaded typescript-language-server, dartls`; `lsp status` → both **ready**
- TS: go-to-definition `AppModule` from `backend/src/main.ts` → resolves `backend/src/app.module.ts:103` (cross-file works)
- Dart: hover on `package:flutter/material.dart` in `frontend/lib/main.dart` → full docs (analysis server live)
- `omp config get tools.approval` → `{"generate_image":"deny"}`
- MCP changes (dedup + node_repl) take effect on **next OMP session** / `/mcp reload` — cannot be observed from inside the session that made them. Verify with `/mcp list`: expect exactly one `context7` (plugin-sourced) and no `node_repl`.

## Notes for next session

- If `/mcp list` still shows two context7 servers, the plugin copy's registered name differs — run `/mcp list` to get exact names and adjust `disabledServers`.
- LSP now available for both tiers: use `lsp references` before touching exported TS/Dart symbols (per house rules).
- Pending from the same conversation: dedup of tripled deploy docs across `AGENTS.md`/`CLAUDE.md`/`.cursor/rules/production-vm-deploy.mdc` — user wants to sort the `.cursor`/`.claude`/`AGENTS.md` instruction mess in a follow-up.
- `playwright` MCP remains defined in `~/.omp/agent/mcp.json` but was not mounted this session — candidate for removal if it never connects (built-in `browser` covers it).
