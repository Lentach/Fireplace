#!/usr/bin/env bash
# One-time setup for encrypted nightly backups on the Fireplace VM.
#
# WHY THIS EXISTS: backup-db.sh is written and verified, but until a passphrase
# exists AND a cron entry runs it, there are effectively NO backups (or, worse,
# UNENCRYPTED ones — backup-db.sh skips .env and warns if no passphrase). This
# script closes that gap: it stores your passphrase in a 0600 file (never on the
# cron line / argv) and installs the daily cron job, idempotently.
#
# THREAT MODEL NOTE (metadata privacy): a DB dump cannot decrypt any message
# (Signal private keys live only on devices), but it DOES contain the contact
# graph, usernames, timestamps, push tokens and bcrypt hashes. Encrypting the
# backup at rest is what turns "seized/stolen backup = full metadata dump" into
# "seized backup = opaque AES256 blob". STORE THE PASSPHRASE OFF THE VM.
#
# Usage (on the VM):  cd ~/fireplace && ./setup-backup-cron.sh
# Re-runnable: updates the passphrase and/or replaces the existing cron line.
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$REPO_DIR"

PASS_DIR="${PASS_DIR:-$HOME/.config/fireplace}"
PASS_FILE="${BACKUP_PASSPHRASE_FILE:-$PASS_DIR/backup.pass}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/fireplace-backups}"
CRON_HOUR="${CRON_HOUR:-4}"          # daily at 04:00 by default
CRON_TAG="# fireplace-backup"         # marker used to find/replace our cron line

if [[ ! -x "$REPO_DIR/backup-db.sh" ]]; then
  echo "ERROR: $REPO_DIR/backup-db.sh not found or not executable." >&2
  echo "       Run this from the repo root on the VM (cd ~/fireplace)." >&2
  exit 1
fi

# --- 1. passphrase file (0600), never echoed, never on argv ---------------------
if [[ -s "$PASS_FILE" ]]; then
  echo "==> Passphrase file already exists at $PASS_FILE"
  read -r -p "    Replace it? [y/N] " reply
  [[ "$reply" == [yY] ]] && rm -f "$PASS_FILE"
fi

if [[ ! -s "$PASS_FILE" ]]; then
  mkdir -p "$PASS_DIR"; chmod 700 "$PASS_DIR"
  echo "==> Enter the backup passphrase (input hidden). STORE IT OFF THE VM too —"
  echo "    an encrypted backup is useless if the only copy of the key dies with the box."
  read -r -s -p "    Passphrase: " pass1; echo
  read -r -s -p "    Confirm:    " pass2; echo
  if [[ -z "$pass1" || "$pass1" != "$pass2" ]]; then
    echo "ERROR: empty or mismatched passphrase — aborting, nothing written." >&2
    exit 1
  fi
  # umask so the file is created 0600 from the start (no readable window).
  ( umask 077; printf '%s' "$pass1" > "$PASS_FILE" )
  chmod 600 "$PASS_FILE"
  unset pass1 pass2
  echo "==> Wrote $PASS_FILE (chmod 600)."
fi

# --- 2. optional offsite bucket -------------------------------------------------
echo
echo "==> Offsite copy (optional). Leave blank to keep backups local-only."
echo "    A GCS bucket path looks like: gs://your-fireplace-backups"
read -r -p "    BACKUP_GCS_BUCKET (blank = none): " gcs_bucket

# --- 3. install/replace the cron line ------------------------------------------
mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"

if [[ -n "$gcs_bucket" ]]; then
  cron_cmd="cd $REPO_DIR && BACKUP_GCS_BUCKET=$gcs_bucket ./backup-db.sh >> $BACKUP_DIR/backup.log 2>&1"
else
  cron_cmd="cd $REPO_DIR && ./backup-db.sh >> $BACKUP_DIR/backup.log 2>&1"
fi
cron_line="0 $CRON_HOUR * * * $cron_cmd $CRON_TAG"

# Preserve every existing cron line EXCEPT our previous fireplace-backup marker.
existing="$(crontab -l 2>/dev/null | grep -vF "$CRON_TAG" || true)"
printf '%s\n%s\n' "$existing" "$cron_line" | sed '/^$/d' | crontab -

echo
echo "==> Installed cron (daily $(printf '%02d' "$CRON_HOUR"):00):"
echo "    $cron_line"
echo
echo "==> Verify now with a manual run:"
echo "      cd $REPO_DIR && ./backup-db.sh"
echo "    Then confirm encrypted artifacts (*.gpg) landed in $BACKUP_DIR and, if set,"
echo "    in $gcs_bucket. Decrypt-test one dump OFF the VM before trusting it:"
echo "      gpg --batch --pinentry-mode loopback --passphrase-file <your-copy> -d chatdb-*.dump.gpg > /tmp/t.dump && head -c4 /tmp/t.dump  # expect: PGDMP"
echo "==> Done."
