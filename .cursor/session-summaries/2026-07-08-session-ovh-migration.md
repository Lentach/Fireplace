# GCP → OVH production migration — EXECUTED, DNS cut over, zero data loss

**Date:** 2026-07-08

## What was done

Executed the full migration runbook (prep evidenced in `.planning/hetzner-migration-prep/findings.md`, verdict GO). Production now serves from **OVH VPS-1 `vps-53b896a3` @ 51.68.138.13** (Warszawa, 2c/4GB+2G swap, Ubuntu 24.04, `ubuntu@`, key-only SSH); FreeDNS A record flipped from 34.118.79.68 → 51.68.138.13 by the owner. GCP box left running as a temporary nginx **relay → VPS** for stale-DNS clients (TTL 3600); decommission is a separate user-approved step after days of stability.

Phases: (1) preflight — SSH both boxes, captured GCP's real nginx/TLS/compose serving setup; (2) target setup — apt upgrade+reboot, Docker 29.6.1+compose v5.3.1, ufw 22/80/443, 2G swap, clone master 283ecb7 (drift vs deployed cf6c51c proven docs-only); (3) staging — `.env` + backup passphrase file moved GCP→VPS via base64-over-SSH pipes (sha256-verified, never displayed), nginx config replicated (root path olek292→ubuntu), live `/etc/letsencrypt` copied (cert fingerprint match, valid to Aug 8), certbot timer armed, `deploy-backend.sh` green after aligning fresh pgdata password with `.env` (`ALTER USER` fed from file); (4) data — fresh `backup-db.sh` set, artifacts sha256-verified through PC transit, atomic `restore-db.sh` + media volume extract, **parity exact** (11 tables + 31 media files); (5) pre-cutover — frontend 0.0.95/283ecb7 built on PC and published (deploy-web.config.ps1 → Method B `ubuntu@51.68.138.13`), full HTTPS checks via `--resolve`, owner smoke test over PC hosts override: 2 fresh accounts, live E2E text/emote/image/ping/GIF all working, footer `0.0.95 · 283ecb7`; (6) cutover — GCP backend frozen, final delta backup 034813Z restored on VPS (messages 424+6 expired-by-design = source 430 — verified via `"expiresAt" < now()`, VPS cleanup log "Deleted 6 expired messages"), GCP nginx swapped to staged+prevalidated relay (~2.5 min user-visible pause), owner flipped FreeDNS; (7) post — nightly encrypted backup cron installed on VPS (`setup-backup-cron.sh`, 04:00, live-fire run + `PGDMP` decrypt probe — GCP NEVER had this), live traffic confirmed through relay (websocket 101, media, VAPID init), docs updated.

## Key files

- `deploy-web.ps1` — Method B swap now `chmod -R a+rX frontend-build` (Ubuntu 24.04 scp lands 700 → nginx 500); file also mysteriously vanished from the working tree mid-session, restored via `git checkout --`
- `deploy-web.config.ps1` (gitignored) — `$VmSshTarget = "ubuntu@51.68.138.13"`, gcloud lines commented for rollback
- `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/production-vm-deploy.mdc` — production sections rewritten GCP→OVH (incl. restore-db version-env trap, chmod trap, relay note)
- `.planning/ovh-migration/{task_plan,progress}.md` (gitignored) — full phase log incl. gotchas
- GCP `/etc/nginx/sites-available/fireplace-relay` — active relay config; original `fireplace` config preserved for rollback
- VPS crontab — `0 4 * * * cd /home/ubuntu/fireplace && ./backup-db.sh >> ~/fireplace-backups/backup.log 2>&1`

## Verification

- Parity: `migration-verify.sh` (temp, removed from both boxes) — identical table counts + media counts source vs target at both syncs; expired-message delta explained and SQL-verified
- HTTPS on VPS: `/health` ok, `/version` 0.0.95/283ecb7 truthful, `/version.json` 0.0.95, index/flutter.js/socket.io 200 — via `curl --resolve` at 51.68.138.13
- Relay: same checks green via `--resolve` at 34.118.79.68 (GCP) after activation; GCP→VPS reachability + `nginx -t` prevalidated at zero downtime BEFORE freezing
- Owner device tests: 2-account E2E round trip on VPS (text/emote/image/ping/GIF); post-cutover live traffic in VPS logs (websocket 101 via relay)
- Backups: live-fire `backup-db.sh` on VPS → 3 gpg artifacts, decrypt probe `PGDMP`

## Notes for next session

- **GCP decommission is OWED** — only after user confirms days of stable operation; then also remove the PC `migration-transit` dir and consider offsite backups (GCS section in deploy rule is GCP-era; VPS has OVH panel backups + local cron only)
- Old GCP box: backend STOPPED, db container still up, nginx relaying. Rollback path (first hours only): revert FreeDNS to 34.118.79.68 + swap GCP nginx symlink back + start backend — but any messages written to VPS after cutover would need reverse-sync
- DNS propagation: TTL 3600; relay makes it a non-event. Check `nslookup fireplace.ignorelist.com 8.8.8.8` shows 51.68.138.13 before assuming full drift
- PC hosts override removal pending owner confirmation (one-liner given)
- `%TEMP%pre30_send.dart` junk file in repo root — owner's leftover, not touched
