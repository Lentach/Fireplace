# Hetzner migration prep — guided pre-migration checklist (no runbook started)

**Date:** 2026-07-06

## What was done

Pre-migration preparation for moving Fireplace (GCP VM 34.118.79.68 → Hetzner Cloud, DE). Production kept read-only except one sanctioned backup-script run and a user-approved `gnupg` install. No DNS changes; no server provisioned.

- **GCP access verified:** `gcloud compute ssh olek292@fireplace-server --zone europe-central2-a` works (SSH_OK, VM up 20+ days, Ubuntu 24.04.4).
- **Data sizing:** pgdata **65 MB**, media **17 MB**, VM disk 13G/29G → **no Hetzner Volume needed** (40 GB target is ~30x headroom).
- **Plan/pricing (official price list, eff. 2026-06-15):** CX22 discontinued → **CX23** (2 vCPU/4 GB/40 GB): €5.49/mo + IPv4 €0.71/mo ≈ **€6.20/mo excl. VAT**, hourly-capped.
- **SSH keypair generated on PC:** `~\.ssh\id_ed25519`, fingerprint `SHA256:DMwrryE//VwcSsabyqjH/EZIRSAMGGctNhD6XiHsXjM` — public key still needs adding to the Hetzner project.
- **Backups had NEVER run on the VM** (no pass file/cron/dir) and **gpg was missing** — installed `gnupg 2.4.4` (user-approved). Full dry-run with throwaway passphrase: exit 0, gpg AES256 artifacts, decrypt roundtrip → `PGDMP`, byte-exact scp to PC; test artifacts deleted both sides.
- **DNS:** A record `fireplace.ignorelist.com → 34.118.79.68` confirmed live; user's FreeDNS edit access NOT yet proven.

## Key files

- `.planning/hetzner-migration-prep/findings.md` — full evidence + blocked-on list (resume point)
- `backup-db.sh` — verified working end-to-end on the VM (first time ever exercised there)

## Verification

- `gcloud compute ssh ... --command "echo SSH_OK && hostname"` → SSH_OK / fireplace-server
- `sudo du -sh --block-size=1M .../fireplace_pgdata/_data .../fireplace_media_storage/_data` → 65 / 17 MB
- `BACKUP_PASSPHRASE=<throwaway> ./backup-db.sh` → EXIT_CODE=0, 3 `.gpg` artifacts
- `gpg --decrypt ... | head -c 5` → `PGDMP`
- `gcloud compute scp` → 273759 B byte-exact on PC
- `nslookup fireplace.ignorelist.com` → 34.118.79.68

## Notes for next session

**PIVOT (same day): Hetzner banned the user's account at signup** (risk-scoring, no reason, re-registration blocked) — Hetzner-specific items dead. Alternatives researched; **OVH VPS-1 2027 verified live in the PL configurator: 2 vCore/4 GB/40 GB NVMe, 16.32 PLN net/mo (~€3.85, 12-mo commit), Warsaw DC auto-preselected, daily backups included** — cheaper than the dead Hetzner plan and better latency. netcup (€5.91/mo) and Contabo (€4.99, mandatory KYC) are fallbacks.

**BOX LIVE + HANDOFF (2026-07-08 ~02:05 UTC):** VPS delivered, reinstalled, verified — `vps-53b896a3` @ **51.68.138.13**, Ubuntu 24.04.4 x86_64, Warsaw os-waw2, 36G free, 3.7Gi RAM, key-only SSH (`ssh -i C:/Users/Lentach/.ssh/id_ed25519 ubuntu@51.68.138.13`) + passwordless sudo green. OVH gotcha for posterity: the image ships `ubuntu` with an EXPIRED emailed temp password that blocks BatchMode even after successful key auth — cleared by a single interactive login + password change (new password in user's password manager). **Fresh agent entry point: `.planning/hetzner-migration-prep/findings.md` → HANDOFF block at top**, then the migration runbook prompt (GCP → 51.68.138.13; `apt upgrade` early; DNS cutover LAST; OVH panel 2FA still owed by user).

**Verdict: GO (2026-07-08 01:19 UTC)** — all gates closed in the continued session: (1) **OVH** chosen; account + 2FA + SSH key `lentach-pc` registered; **VPS-1 2027 PAID** (2 vCore/4 GB/40 GB NVMe, Warsaw, month-to-month, 23,62 zł brutto/mies., free Automated Backup promo) — delivery pending, first step after delivery = panel **Reinstall → Ubuntu 24.04 + key** (order flow lacked the key dropdown; preselected 26.04 caught and corrected pre-payment); (2) FreeDNS edit access screenshot-proven (`Fireplace.ignorelist.com A 34.118.79.68` editable in user's account); (3) backup passphrase: user's 10-char attempt rejected; one generated value **leaked into chat via a plink paste-mangle → rotated**; final 32-char openssl value in password manager; real `backup-db.sh` produced 3 gpg artifacts, decrypt-probe `PGDMP`, all downloaded to PC `%USERPROFILE%\fireplace-backups\` (chatdb 291,786 B / media 18,683,340 B / env 551 B). Exit-1 scare resolved: `SCRIPT_RC=0` measured directly; plink transport artifact. **The migration runbook may start** — re-map its Hetzner console steps to OVH (target: OVH VPS-1 2027 Warsaw). Notes: VM has gnupg 2.4.4 (only prod change, user-approved); backup cron still NOT configured (post-migration task on the new server). Resume state: `.planning/hetzner-migration-prep/findings.md`.
