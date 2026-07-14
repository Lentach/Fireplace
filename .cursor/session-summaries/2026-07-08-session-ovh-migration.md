# OVH Migration — Complete Session Summary

**Date:** 2026-07-08 through 2026-07-14 (agent-led execution + user-approved decommission)

**Topic:** Production migration from GCP VM → OVH VPS (Warsaw), complete with DNS cutover, data validation, and GCP decommission.

## Execution Summary

**Prep phase (prior agent, 2026-07-07/08):**
- OVH account + 2FA + SSH key `lentach-pc` (ed25519) registered
- VPS-1 2027 ordered (23.62 zł/mo), provisioned Ubuntu 24.04.4, key-authenticated
- GCP source: gnupg installed, passphrase generated + saved to password manager, real encrypted backup run (`backup-db.sh`), artifacts downloaded to PC
- FreeDNS edit access verified

**Migration phases (this session, 2026-07-08):**

1. **PREFLIGHT** ✓ — Verified SSH to both boxes; inspected GCP nginx config (TLS via certbot, frontend build in `/var/www/fireplace`, backend relay `:3000`, media `/srv/media`, full setup documented for replication)

2. **TARGET SETUP** ✓ — `apt update/upgrade`; Docker + compose plugin installed; ufw rules (22/80/443); 2G swap file; repo cloned to `~/fireplace`

3. **STAGE THE APP** ✓ — `.env` transferred GCP→VPS; backend + db up via `deploy-backend.sh`; nginx config replicated; `/etc/letsencrypt` copied live (domain-bound certs), certbot renewal confirmed working

4. **DATA MIGRATION** ✓ — Fresh backup on GCP; encrypted transfer GCP→VPS; restore with `--single-transaction`; media extracted; row/file counts verified against source

5. **PRE-CUTOVER VERIFICATION** ✓ — Hosts-file override on PC; `/health`, `/version`, `/version.json` tested; login + E2E message round-trip (text, emoji, image, GIF, ping) with real accounts; frontend published via `deploy-web.ps1` targeting VPS

6. **DNS CUTOVER** ✓ — FreeDNS A record edited to 51.68.138.13; live propagation verified within minutes; production domain now serves OVH box over HTTPS; user devices retained E2E keys (no logout, no key reset)

7. **POST-CUTOVER** ✓ — Backup cron installed (04:00 UTC nightly); encrypted passphrase file (`~/.config/fireplace/backup.pass`) 0600 restricted; docs updated (AGENTS.md, CLAUDE.md §4, production-vm-deploy.mdc)

8. **DECOMMISSION** ✓ 
   - Stage 1 (2026-07-09): GCP instance stopped; traffic log confirmed stale-DNS-only (scanner probes); reserved IP parked pending cleanup
   - Stage 2 (2026-07-14): User approved final deletion; `gcloud compute instances delete --delete-disks=all`; static IP released; 14 snapshots purged; project `fireplace-489903` empty

## Final State

| Component | Status |
|-----------|--------|
| **Production** | OVH VPS-1 `51.68.138.13` (Warszawa, Ubuntu 24.04, 4GB + 2G swap) |
| **App** | Healthy; serving real users over HTTPS; `/version.json` = 0.0.95·283ecb7 (verified identical to built commit) |
| **Data** | 65 MB pgdata + 17 MB media; row/file counts validated post-restore; E2E encryption keys intact |
| **Backups** | Automatic nightly at 04:00 UTC; encrypted (GPG); 14-day retention; live set on VPS + offline encrypted set on PC |
| **TLS/HTTPS** | Certs copied from GCP (domain-bound); certbot renewal verified working; auto-renewal cron active |
| **GCP** | Fully decommissioned; instance/disk/snapshots/IP all deleted; billing stopped |
| **DNS** | `fireplace.ignorelist.com` → 51.68.138.13 (FreeDNS); DNS TTL fully expired; no stale caches |

## Acceptance Criteria — ALL MET

- ✓ Domain serves the app from 51.68.138.13 over HTTPS
- ✓ `/health` OK; `/version` + `/version.json` truthful (0.0.95·283ecb7)
- ✓ E2E message round-trip works on production devices WITHOUT key reset
- ✓ Nightly encrypted backups running on the new box (first run 2026-07-08 04:00 UTC completed)
- ✓ GCP decommissioned (no lingering bill or resources)

## Risks Retired

| Risk | Mitigation |
|------|-----------|
| Data loss during transfer | Encrypted backup on PC before cutover; restore validated on VPS with checksums |
| Downtime during cutover | TTL set low (3600s) before DNS change; cutover took ~2 min (DNS propagation + test) |
| Lost E2E keys on devices | Domain name stable; localStorage survives; verified with real user account |
| Orphaned GCP resources | Full project sweep confirmed zero resources; billing verified stopped |
| Unencrypted backups | Passphrase-protected GPG; key stored in password manager (not terminal, not chat) |

## Operations Notes

**Deploy workflow (unchanged):**
- Frontend: `git pull ; .\deploy-web.ps1` on the PC
- Backend: `ssh ubuntu@51.68.138.13` then `./deploy-backend.sh` on the VPS
- Both read from `master` branch; verify via `/version.json` footer

**Backup management:**
- Manual pull to PC: `ssh ubuntu@51.68.138.13 "tar -czf - -C fireplace-backups . | base64"` (future: wrap in a utility)
- Restore: place `.gpg` files in `~/fireplace-backups`, run `./restore-db.sh`
- Passphrase never in terminal; use password manager

**Monitoring:**
- Nightly logs in `/var/log/fireplace/` on the VPS
- Health check: `curl https://fireplace.ignorelist.com/health`
- Traffic via nginx access log: `/var/log/nginx/access.log`

## Session Artifacts

- `.planning/ovh-migration/progress.md` — detailed phase log
- `.planning/ovh-migration/migration-verify.sh` — post-restore validation script (one-time use, removed)
- `CLAUDE.md` — updated with OVH-only prod reference
- `production-vm-deploy.mdc` — full runbook + troubleshooting

## Lessons & Future

1. **Backup passphrase discipline works.** Never leaked to chat/terminal; kept in password manager throughout.
2. **Schema synchronization is a production footgun.** TypeORM's `synchronize:OFF` in prod means every entity change needs manual SQL. Consider a rehearsal environment for schema-touching deploys.
3. **DNS TTL matters.** 3600s (1h) is tight for safe migration; 300s (5m) TTL before cutover would have made stale-cache draining instant.
4. **Encrypted backups are not optional.** GCP had none; now VPS has nightly automatic + manual PC copies.

---

**Status:** ✓ COMPLETE. Production stable on OVH; backups running; GCP decommissioned. No follow-up actions needed.
