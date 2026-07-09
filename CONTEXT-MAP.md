# Context Map — Fireplace

This repo is multi-context. Per-context domain language lives next to the code:

| Context  | Glossary               | Scoped ADRs         | Covers                                          |
| -------- | ---------------------- | ------------------- | ----------------------------------------------- |
| Backend  | `backend/CONTEXT.md`   | `backend/docs/adr/` | NestJS API, WS gateway, Postgres, Signal server |
| Frontend | `frontend/CONTEXT.md`  | `frontend/docs/adr/`| Flutter app, PWA, providers, Signal client      |

System-wide decisions (wire contracts, versioning, deploy) live in `docs/adr/` at the root.

Per-context `CONTEXT.md` files are created lazily by `/domain-modeling` (via `/grill-with-docs`) — absence is normal, not an error.
