# Backup Hardening Implementation Plan

> **For agentic workers:** implemented inline this session. Steps use checkbox (`- [ ]`) tracking.

**Goal:** Harden the Fireplace VM backup so the encryption passphrase never sits in crontab/`ps`, disaster-recovery secrets (`.env`) are captured (encrypted-only), and offsite GCS is a one-command setup.

**Architecture:** Pure shell changes to the existing `backup-db.sh` / `restore-db.sh` plus a new `setup-backup-bucket.sh` helper and a lifecycle JSON. No backend/app code changes; nothing auto-deploys (feature branch → merge to `master`, then run on VM).

**Tech Stack:** bash, gpg (AES256 symmetric, `--passphrase-file`), pg_dump/pg_restore (docker compose exec), gsutil/gcloud.

---

## Background / current state

- `backup-db.sh` encrypts with `gpg --passphrase "$BACKUP_PASSPHRASE"` — the passphrase is (a) required inline in the crontab line and (b) visible in `ps` (argv) during the run.
- `.env` (`JWT_SECRET`, VAPID keys, DB creds) is **gitignored, VM-only, and not backed up** — losing the VM loses it.
- GCS offsite already supported via `BACKUP_GCS_BUCKET`, but bucket creation/privacy/lifecycle/IAM is undocumented manual work.

## Security decisions (locked)

- **Passphrase never on argv.** Always feed gpg via `--passphrase-file`. If `BACKUP_PASSPHRASE` (env) is the only source, write it to a `mktemp` file `chmod 600`, use it, delete it (trap). Prefer a persistent `BACKUP_PASSPHRASE_FILE` (default `~/.config/fireplace/backup.pass`).
- **Refuse weak passphrase-file perms.** If the file is group/other-readable, abort (stat check).
- **`.env` is backed up ONLY when encryption is active.** No passphrase → skip `.env` with a loud warning (never write secrets in cleartext).
- **Restore never auto-overwrites live `.env`.** `restore-db.sh` stays DB-only; `.env` recovery is a documented manual extract so a restore can't silently clobber rotated secrets.

## File Structure

- Modify `backup-db.sh` — passphrase resolution helper; gpg via `--passphrase-file`; add encrypted `.env` to the set.
- Modify `restore-db.sh` — decrypt via `--passphrase-file` using the same resolver; keep DB-only.
- Create `setup-backup-bucket.sh` — one-time private bucket + lifecycle + IAM (user runs on GCP).
- Create `backup-bucket-lifecycle.json` — lifecycle rule (delete > N days).
- Modify `.cursor/rules/production-vm-deploy.mdc` — update Backups section (passphrase file, `.env`, bucket setup, `.env` restore).

---

### Task 1: Passphrase resolver (shared logic, no argv leak)

**Files:** Modify `backup-db.sh`, `restore-db.sh`.

- [ ] **Step 1:** Add near the top of `backup-db.sh` (after the existing config vars), a resolver that yields a passphrase **file** path and validates perms:

```bash
BACKUP_PASSPHRASE_FILE="${BACKUP_PASSPHRASE_FILE:-$HOME/.config/fireplace/backup.pass}"
_PASS_TMP=""
cleanup_pass() { [[ -n "$_PASS_TMP" ]] && rm -f "$_PASS_TMP"; }
trap cleanup_pass EXIT

# Echoes a path to a passphrase file (mode 600) or empty string if none available.
resolve_pass_file() {
  if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
    _PASS_TMP="$(mktemp)"; chmod 600 "$_PASS_TMP"
    printf '%s' "$BACKUP_PASSPHRASE" > "$_PASS_TMP"
    echo "$_PASS_TMP"; return 0
  fi
  if [[ -f "$BACKUP_PASSPHRASE_FILE" ]]; then
    local mode; mode="$(stat -c '%a' "$BACKUP_PASSPHRASE_FILE" 2>/dev/null || stat -f '%Lp' "$BACKUP_PASSPHRASE_FILE")"
    if [[ "$mode" != "600" && "$mode" != "400" ]]; then
      echo "ERROR: $BACKUP_PASSPHRASE_FILE must be chmod 600 (is $mode)" >&2; return 1
    fi
    echo "$BACKUP_PASSPHRASE_FILE"; return 0
  fi
  echo ""; return 0
}
gpg_enc() { gpg --batch --yes --pinentry-mode loopback --passphrase-file "$1" --symmetric --cipher-algo AES256 "$2"; }
```

- [ ] **Step 2:** Replace the existing encryption block in `backup-db.sh`:

```bash
PASS_FILE="$(resolve_pass_file)" || exit 1
if [[ -n "$PASS_FILE" ]]; then
  echo "==> encrypting (gpg AES256, passphrase-file)"
  for f in "$db_file" "$media_file"; do
    [[ -f "$f" ]] || continue
    gpg_enc "$PASS_FILE" "$f" && rm -f "$f"
  done
else
  echo "WARN: no passphrase (set BACKUP_PASSPHRASE or create $BACKUP_PASSPHRASE_FILE, chmod 600) — backups UNENCRYPTED in $BACKUP_DIR."
fi
```

- [ ] **Step 3:** In `restore-db.sh`, replace the decrypt block to use the same resolver + `--passphrase-file`:

```bash
if [[ "$SRC" == *.gpg ]]; then
  PASS_FILE="$(resolve_pass_file)" || exit 1
  [[ -n "$PASS_FILE" ]] || { echo "ERROR: encrypted dump needs BACKUP_PASSPHRASE or $BACKUP_PASSPHRASE_FILE" >&2; exit 1; }
  tmp="$(mktemp)"
  gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASS_FILE" -o "$tmp" -d "$SRC"
  SRC="$tmp"
fi
```
(restore-db.sh needs the same `resolve_pass_file`/`BACKUP_PASSPHRASE_FILE`/trap block copied near its top.)

- [ ] **Step 4:** `bash -n backup-db.sh && bash -n restore-db.sh` → no syntax errors.

- [ ] **Step 5:** gpg round-trip test (real, local):

```bash
pf=$(mktemp); printf 'testpass' > "$pf"; chmod 600 "$pf"
echo "hello-secret" > /tmp/p.txt
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$pf" --symmetric --cipher-algo AES256 /tmp/p.txt
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$pf" -o /tmp/p.out -d /tmp/p.txt.gpg
diff <(echo hello-secret) /tmp/p.out && echo "ROUND-TRIP OK"
rm -f "$pf" /tmp/p.txt /tmp/p.txt.gpg /tmp/p.out
```
Expected: `ROUND-TRIP OK`.

- [ ] **Step 6:** Commit.

### Task 2: Back up `.env` (encrypted-only)

**Files:** Modify `backup-db.sh`.

- [ ] **Step 1:** After the DB+media encryption loop (PASS_FILE known), add:

```bash
if [[ -n "$PASS_FILE" && -f "$ENV_FILE" ]]; then
  echo "==> backing up .env (encrypted)"
  env_file_out="$BACKUP_DIR/env-$ts.gpg"
  gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASS_FILE" \
    --symmetric --cipher-algo AES256 -o "$env_file_out" "$ENV_FILE"
elif [[ -f "$ENV_FILE" ]]; then
  echo "WARN: skipping .env backup — no passphrase (secrets are never written unencrypted)."
fi
```

- [ ] **Step 2:** Extend retention prune + GCS glob to include `env-*`:

```bash
find "$BACKUP_DIR" -type f \( -name 'chatdb-*' -o -name 'media-*' -o -name 'env-*' \) -mtime +"$RETENTION_DAYS" -delete
```

- [ ] **Step 3:** `bash -n backup-db.sh`. Commit.

### Task 3: GCS offsite setup helper

**Files:** Create `setup-backup-bucket.sh`, `backup-bucket-lifecycle.json`.

- [ ] **Step 1:** `backup-bucket-lifecycle.json`:

```json
{ "rule": [ { "action": {"type": "Delete"}, "condition": {"age": 30} } ] }
```

- [ ] **Step 2:** `setup-backup-bucket.sh`:

```bash
#!/usr/bin/env bash
# One-time: create a PRIVATE GCS bucket for Fireplace backups + lifecycle + IAM.
# Usage: BUCKET=gs://fireplace-backups-xyz PROJECT=my-proj SA=vm-sa@my-proj.iam.gserviceaccount.com ./setup-backup-bucket.sh
set -euo pipefail
: "${BUCKET:?set BUCKET=gs://...}"; : "${PROJECT:?set PROJECT=...}"
LOCATION="${LOCATION:-europe-central2}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
gcloud storage buckets create "$BUCKET" --project "$PROJECT" --location "$LOCATION" \
  --uniform-bucket-level-access --public-access-prevention 2>/dev/null || echo "bucket exists?"
gcloud storage buckets update "$BUCKET" --lifecycle-file="$REPO_DIR/backup-bucket-lifecycle.json"
if [[ -n "${SA:-}" ]]; then
  gcloud storage buckets add-iam-policy-binding "$BUCKET" \
    --member="serviceAccount:$SA" --role="roles/storage.objectAdmin"
fi
echo "Done. Set in cron: BACKUP_GCS_BUCKET=$BUCKET"
```

- [ ] **Step 3:** `bash -n setup-backup-bucket.sh`; validate JSON (`python -c 'import json,sys;json.load(open(sys.argv[1]))' backup-bucket-lifecycle.json`). Commit.

### Task 4: Docs

**Files:** Modify `.cursor/rules/production-vm-deploy.mdc` (Backups & monitoring section).

- [ ] **Step 1:** Update to document: passphrase file (`~/.config/fireplace/backup.pass`, chmod 600) so the cron line carries no secret; `.env` is in the encrypted set; `setup-backup-bucket.sh` for offsite; `.env` restore is manual (`gpg -d env-<ts>.gpg > ~/fireplace/.env` then `./deploy-backend.sh`).

- [ ] **Step 2:** Commit.

---

## Self-Review

- **Coverage:** passphrase-file ✓ (T1), `.env` encrypted-only ✓ (T2), GCS one-command ✓ (T3), docs ✓ (T4).
- **Placeholders:** none — all code shown.
- **Consistency:** `resolve_pass_file`/`PASS_FILE`/`BACKUP_PASSPHRASE_FILE`/`_PASS_TMP` names consistent across both scripts; `gpg --passphrase-file` everywhere.
- **Risk:** restore stays DB-only (no `.env` clobber); no-passphrase path never writes secrets; perms refused if not 600/400.

## Verification (whole feature)

- `bash -n` clean on all four scripts.
- gpg `--passphrase-file` round-trip passes locally (Task 1 Step 5).
- JSON validates.
- Acceptance on VM: create `~/.config/fireplace/backup.pass` (chmod 600), run `./backup-db.sh`, confirm `chatdb-*.gpg`, `media-*.gpg`, `env-*.gpg` appear; `gpg -d` one and `pg_restore -l` it.

---

## Review findings (self-review, security-focused) — INCORPORATED before implementation

**BLOCKER 1 — temp passphrase file leaks (cleartext on disk).** The draft used
`PASS_FILE="$(resolve_pass_file)"`. The function runs in a command-substitution **subshell**,
so `_PASS_TMP` (the mktemp holding the plaintext passphrase) is set in the subshell and **lost in
the parent** → the `EXIT` trap sees an empty `_PASS_TMP` and never deletes it → the plaintext
passphrase persists on disk after every run. **Fix:** resolve in the **parent scope** — the function
sets globals `PASS_FILE`/`_PASS_TMP` directly (no `$(...)`), called as `resolve_pass_file || exit 1`.
Trap on `EXIT INT TERM`; `shred -u` the temp (fallback `rm -f`). Corrected code below supersedes
Task 1 Step 1.

```bash
BACKUP_PASSPHRASE_FILE="${BACKUP_PASSPHRASE_FILE:-$HOME/.config/fireplace/backup.pass}"
PASS_FILE=""
_PASS_TMP=""
cleanup_pass() { [[ -n "$_PASS_TMP" ]] && { shred -u "$_PASS_TMP" 2>/dev/null || rm -f "$_PASS_TMP"; }; }
trap cleanup_pass EXIT INT TERM

# Sets global PASS_FILE to a 0600 passphrase file, or "" if none. No subshell (trap-safe).
resolve_pass_file() {
  if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
    _PASS_TMP="$(mktemp)"; chmod 600 "$_PASS_TMP"
    printf '%s' "$BACKUP_PASSPHRASE" > "$_PASS_TMP"
    PASS_FILE="$_PASS_TMP"; return 0
  fi
  if [[ -f "$BACKUP_PASSPHRASE_FILE" ]]; then
    local mode; mode="$(stat -c '%a' "$BACKUP_PASSPHRASE_FILE" 2>/dev/null || stat -f '%Lp' "$BACKUP_PASSPHRASE_FILE")"
    if [[ "$mode" != "600" && "$mode" != "400" ]]; then
      echo "ERROR: $BACKUP_PASSPHRASE_FILE must be chmod 600 (is $mode)" >&2; return 1
    fi
    PASS_FILE="$BACKUP_PASSPHRASE_FILE"; return 0
  fi
  PASS_FILE=""; return 0
}
resolve_pass_file || exit 1   # used in BOTH backup-db.sh and restore-db.sh
```

**SHOULD-FIX 2 — passphrase recoverability (off-VM).** An encrypted backup is useless if the only
copy of the passphrase dies with the VM. Docs MUST state: store the passphrase in a password manager
/ secret manager, NOT only in `~/.config/fireplace/backup.pass`.

**SHOULD-FIX 3 — `.env` restore stays manual (no auto-clobber).** Correct call. Document recovery:
`gpg -d env-<ts>.gpg > /tmp/env.restored`, operator reviews, then places it — never overwrite a
rotated live `.env` automatically.

**SHOULD-FIX 4 — lifecycle vs local retention.** Bucket lifecycle (30d) and local `RETENTION_DAYS`
(14d) are intentionally independent (offsite keeps longer). Make the lifecycle age configurable and
call out the difference in docs so it isn't read as a bug.

**NICE-TO-HAVE 5 — bucket privacy/portability.** `setup-backup-bucket.sh` already sets
`--uniform-bucket-level-access --public-access-prevention` (good). `stat -c %a` is GNU (VM is Linux),
BSD `stat -f %Lp` fallback kept. Passphrase file = passphrase on first line (gpg strips trailing newline).
