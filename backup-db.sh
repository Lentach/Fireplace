#!/usr/bin/env bash
# Nightly Postgres + media backup for the Fireplace VM.
#
# E2E SAFETY: message bodies are stored ENCRYPTED (Signal ciphertext); the private
# keys that decrypt them live ONLY on devices, never in the DB. A dump therefore
# CANNOT decrypt any message. It DOES contain metadata (usernames, contact graph,
# timestamps), bcrypt password hashes and PUBLIC keys, so treat it as sensitive:
# keep BACKUP_DIR private (0700), set BACKUP_PASSPHRASE to encrypt at rest, and/or
# push to a locked-down bucket via BACKUP_GCS_BUCKET.
#
# Usage:  cd ~/fireplace && ./backup-db.sh
# Cron (daily 04:00):
#   0 4 * * * cd ~/fireplace && BACKUP_PASSPHRASE='...' ./backup-db.sh >> ~/fireplace-backups/backup.log 2>&1
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$REPO_DIR"

COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE="$REPO_DIR/.env"
DB_NAME="${DB_NAME:-chatdb}"
DB_USER="${DB_USER:-postgres}"
MEDIA_VOLUME="${MEDIA_VOLUME:-fireplace_media_storage}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/fireplace-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

compose() { docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
db_file="$BACKUP_DIR/chatdb-$ts.dump"
media_file="$BACKUP_DIR/media-$ts.tar.gz"

echo "==> [$ts] pg_dump $DB_NAME (custom/compressed format)"
compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$db_file"
[[ -s "$db_file" ]] || { echo "ERROR: dump is empty — aborting" >&2; rm -f "$db_file"; exit 1; }

echo "==> tar media volume ($MEDIA_VOLUME)"
if ! docker run --rm -v "$MEDIA_VOLUME":/data:ro -v "$BACKUP_DIR":/backup alpine \
       tar czf "/backup/$(basename "$media_file")" -C /data . ; then
  echo "WARN: media backup skipped (is the volume named '$MEDIA_VOLUME'? check: docker volume ls)"
fi

# Optional encryption at rest (recommended). Requires gpg.
if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "==> encrypting (gpg AES256)"
  for f in "$db_file" "$media_file"; do
    [[ -f "$f" ]] || continue
    gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" \
      --symmetric --cipher-algo AES256 "$f"
    rm -f "$f"
  done
else
  echo "WARN: BACKUP_PASSPHRASE unset — backups are UNENCRYPTED at rest in $BACKUP_DIR (keep it private)."
fi

# Optional offsite copy to a private bucket. Requires gsutil + BACKUP_GCS_BUCKET=gs://your-bucket
if [[ -n "${BACKUP_GCS_BUCKET:-}" ]] && command -v gsutil >/dev/null 2>&1; then
  echo "==> uploading to $BACKUP_GCS_BUCKET"
  gsutil -m cp "$BACKUP_DIR/"*"$ts"* "$BACKUP_GCS_BUCKET/" || echo "WARN: gsutil upload failed"
fi

echo "==> pruning local backups older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -type f \( -name 'chatdb-*' -o -name 'media-*' \) -mtime +"$RETENTION_DAYS" -delete

echo "==> done. Local backups in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR" | grep -E "$ts" || true
