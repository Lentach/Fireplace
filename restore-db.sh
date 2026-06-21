#!/usr/bin/env bash
# Restore a Fireplace Postgres dump produced by backup-db.sh.
#
# DESTRUCTIVE: --clean drops & recreates objects in the target DB. The backend is
# stopped during the restore and started again afterwards.
#
# Usage:  cd ~/fireplace && ./restore-db.sh ~/fireplace-backups/chatdb-YYYYmmddTHHMMSSZ.dump[.gpg]
#   Encrypted (.gpg) dumps need BACKUP_PASSPHRASE set.
#   Media is restored separately (see production-vm-deploy rule).
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <chatdb-*.dump[.gpg]>" >&2; exit 1; }
SRC="$1"
[[ -f "$SRC" ]] || { echo "ERROR: not found: $SRC" >&2; exit 1; }

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$REPO_DIR"
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE="$REPO_DIR/.env"
DB_NAME="${DB_NAME:-chatdb}"
DB_USER="${DB_USER:-postgres}"

compose() { docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

tmp=""
cleanup() { [[ -n "$tmp" ]] && rm -f "$tmp"; }
trap cleanup EXIT

if [[ "$SRC" == *.gpg ]]; then
  [[ -n "${BACKUP_PASSPHRASE:-}" ]] || { echo "ERROR: encrypted dump needs BACKUP_PASSPHRASE" >&2; exit 1; }
  tmp="$(mktemp)"
  gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" -o "$tmp" -d "$SRC"
  SRC="$tmp"
fi

echo "WARNING: this OVERWRITES data in '$DB_NAME'. Ctrl-C within 5s to abort."
sleep 5

echo "==> stopping backend"
compose stop backend
echo "==> pg_restore (clean)"
compose exec -T db pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists < "$SRC"
echo "==> starting backend"
compose up -d backend

echo "==> restore complete. Verify:  curl -fsS http://127.0.0.1:3000/health"
