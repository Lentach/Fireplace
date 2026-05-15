---
inclusion: always
---

# Fireplace — use CLAUDE.md

- **Before** any code change, review, refactor, or architecture discussion in this workspace: read **`CLAUDE.md`** at the repository root (full file). Treat it as the single source of truth for stack, ports, gotchas, and file map unless the actual source code contradicts it — then follow the code and **update `CLAUDE.md`**.
- **After** every meaningful change (behavior, API, env, tests, security): update the relevant section of **`CLAUDE.md`** in the same change when practical.
- Do **not** rely on stale copies of this document from chat history or old rules; always read the file from disk in the project.
- Project knowledge lives in **`CLAUDE.md`** only — do not maintain a parallel long-form project spec in Cursor rules.
