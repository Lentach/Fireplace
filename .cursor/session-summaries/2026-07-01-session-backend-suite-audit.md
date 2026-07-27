# Backend test suite audit

**Date:** 2026-07-01

## What was done
- Audited every backend Jest spec currently in `backend/src/**/*.spec.ts` plus stale `backend/test/app.e2e-spec.ts`.
- Classified tests conservatively: most files valuable, nine weak-but-kept, one useless stale e2e boilerplate deleted.
- Deleted stale Nest boilerplate `backend/test/app.e2e-spec.ts` and its unused `backend/test/jest-e2e.json`; removed the dead `test:e2e` package script and backend CLAUDE command entry.
- Added 18 backend unit tests covering missing critical paths:
  - Auth/session: username#tag login, ambiguous username rejection, refresh-token rotation, expired-token invalidation, logout revoke, revoke-all.
  - Media: JWT guard metadata for upload/message fetch, upload 21 MiB interceptor limit, avatar magic-byte integration, filename traversal rejection.
  - Messaging/push/unread: focused-recipient push skip and negative cases, unread summary query filters.
  - Mappers: reaction JSON, link-preview metadata, conversation pin metadata/pinned message mapping.
- Updated backend test count documentation in `CLAUDE.md` and `AGENTS.md` from 328 to 346 unit tests / 41 suites.
- Ran code review; reviewer approved with one minor non-blocking note that the media FileInterceptor limit test depends on Nest internals.

## Key files
- `AGENTS.md`
- `CLAUDE.md`
- `backend/CLAUDE.md`
- `backend/package.json`
- `backend/src/auth/auth.service.spec.ts`
- `backend/src/auth/refresh-tokens.service.spec.ts`
- `backend/src/chat/mappers/conversation.mapper.spec.ts`
- `backend/src/chat/services/chat-message.service.spec.ts`
- `backend/src/media/media.controller.spec.ts`
- `backend/src/messages/message.mapper.spec.ts`
- `backend/src/messages/messages.service.spec.ts`
- `backend/test/app.e2e-spec.ts` (deleted)
- `backend/test/jest-e2e.json` (deleted)
- `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json` (updated by `graphify update .`)

## Verification
- `node scripts/verify-claude-backend-test-counts.mjs` before changes → `OK: CLAUDE.md matches Jest (328 tests, 41 suites)`.
- `cd backend && npm test` before changes → 41 suites passed, 328 tests passed.
- `cd backend && npm run test:e2e` before deletion → failed on stale `/` Hello World boilerplate spec timeout.
- Targeted tester runs passed for modified specs.
- `cd backend && npm test` after changes → 41 suites passed, 346 tests passed.
- `node scripts/verify-claude-backend-test-counts.mjs` after docs update → `OK: CLAUDE.md matches Jest (346 tests, 41 suites)`.
- `graphify update .` → rebuilt graph, latest run reported 7687 nodes / 10968 edges / 490 communities.

## Notes for next session
- Branch: `test/backend-suite-audit`.
- Still-uncovered high-value areas: destructive chat lifecycle (`clearChatHistory`, delete-for-me/everyone branches beyond pin cleanup, `deleteConversationOnly`, unfriend cleanup), full gateway decorator/throttle matrix, Secret Notes HTTP guard/public-route/ValidationPipe behavior, link-preview DNS-private resolution (not implemented), and deeper message cleanup query branches.
- No app source code was changed; this is test/docs/config cleanup only.
