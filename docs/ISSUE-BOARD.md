# Issue Board (Fireplace) — triage only

Transient triage that sits beside CLAUDE.md (which stays THE source of truth for architecture/
contracts). Update status as work lands. Statuses: OPEN · IN-PROGRESS (branch exists) ·
IN-TESTING · DONE · DEFERRED · PLATFORM-LIMIT.

> ⚠️ Repo is PUBLIC. This lists security-adjacent bugs (auth/E2E). Keep this file LOCAL
> (gitignore it) or scrub sensitive detail before committing.

Last updated: (fill on edit)

---

## 🔴 Critical / high
| Issue | Status | Branch | Notes |
|---|---|---|---|
| Spontaneous logout (idle → login screen; many users) | IN-PROGRESS | `fix/sticky-sessions` | Keys survive (data intact). Suspects: refresh-token TTL / no silent-refresh-on-boot / JWT_SECRET stability. Instrument first. |
| E2E `[decryption failed]` regression | IN-TESTING | (merged?) | Fix = lossless rebuild + stop duplicate send. Verify over long idle → reconnect → backlog. |
| Live messages don't appear in open chat (acts "not viewing") | OPEN | — | Active-conv/socket-room desync on reconnect/resume; add reconcile gap-fill. |

## 🟠 Open / in-progress
| Issue | Status | Branch | Notes |
|---|---|---|---|
| Emoji reactions rework (Signal/Telegram bar) | IN-PROGRESS | `feat/emoji-reactions` | Match screenshot + standard; per-user model + E2E-vs-metadata decision. |
| Message editing | IN-PROGRESS | `feat/message-editing` / `docs/message-editing-design` | Text-only v1; window; keep-history? |
| Edited-message text renders wrong/displaced (overlay) | OPEN | — | Stale/snapshot vs layout displacement; edited + long-press overlay. |
| Emote message layout (P1 indicators-under, P2 iOS missing, P3 jumbo size, P4 inline size) | OPEN | `fix/emote-message-layout` | Needs px numbers confirmed. |
| Emote composer (A native emoji, B scroll-to-newest, C panel anim) | OPEN | `fix/emote-composer-native-scroll-anim` | A decided: native per platform. |
| Android keyboard white-void + hide-lag + false portrait overlay | OPEN | — | interactive-widget meta + event-driven relayout; don't reintroduce scroll-lock. |
| E2E media upload gap (orphan metric + cron grace) | IN-PROGRESS | `fix/media-orphan-grace-and-metric` | Low sev; grace period + observability. |
| Frontend production-readiness review | IN-PROGRESS | `review/frontend-prod-readiness` | Report-first, go/no-go. |
| Test-suite audit (backend / frontend) | IN-PROGRESS | `test/backend-suite-audit`, `test/frontend-suite-audit` | Backend done; frontend + E2E round-trip. |
| GCP → Hetzner migration | OPEN | `chore/migrate-to-hetzner` (planned) | DE, midnight–noon, FreeDNS cutover, carry same JWT_SECRET. |

## 🟡 Deferred (need decision/brainstorm)
| Issue | Notes |
|---|---|
| Reinstall = key/history loss (backup) | Brainstorm: encrypted key+history backup w/ recovery code (NOT multi-device). Security review. |
| Password-reset flow | Keys safe ≠ recoverable if password forgotten + logged out. Non-trivial for E2E. |

## ⚪ Platform limits (accept + document, don't grind)
- iOS PWA keyboard bounce on send · iOS mic re-prompt · iOS web-push `tag`/`getNotifications`
  cross-SW-lifetime · Android numeric app badge (launcher counts cards) · Android deep-Doze push
  deferral (native app fixes) · container-runs-as-root (L-11, minor hardening).

## ✅ Recently done (verify then drop)
- iOS notification group-clear (app-closed), count "5 then 5", monochrome icon, ping media-session.
- Branch cleanup (repo trimmed to master + audit/full-review).
