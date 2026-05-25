# Fireplace documentation

## Active (agents & humans)

| Doc | Purpose |
|-----|---------|
| [CLAUDE.md](../CLAUDE.md) | Single source of truth for stack, gotchas, file map |
| [METADATA.md](./METADATA.md) | Server metadata retention |
| [manual-e2e-testing.md](./manual-e2e-testing.md) | Manual E2E checklist |
| [superpowers/specs/2026-05-24-e2e-decrypt-core-bug-agent-handoff.md](./superpowers/specs/2026-05-24-e2e-decrypt-core-bug-agent-handoff.md) | Current E2E decrypt investigation handoff |

Add new **active** specs under `docs/superpowers/specs/` only while work is in progress. Move to archive when shipped or abandoned.

## Archive

Completed implementation plans, design specs, futures reviews, and old source-of-truth notes live under **[docs/archive/](./archive/)**:

- `archive/plans/` — legacy `docs/plans/`
- `archive/superpowers/plans/` — shipped superpowers plans
- `archive/superpowers/specs/` — shipped design specs (May 2026 and earlier)
- `archive/futures/` — reviews + historical architecture notes

These files are not required for builds; they are kept for history and agent context.
