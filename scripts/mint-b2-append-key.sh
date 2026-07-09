#!/usr/bin/env bash
# Mint an APPEND-ONLY Backblaze B2 application key for backup-db.sh offsite uploads.
#
# Why a script: the B2 web UI cannot create a key without the deleteFiles
# capability, and only the account MASTER application key has writeKeys (the
# capability needed to mint keys). This prompts for the master key, mints a
# bucket-scoped key with [listBuckets, listFiles, readFiles, writeFiles] —
# NO deleteFiles — and prints it ONCE. Secrets are read interactively and
# never touch argv, disk, or shell history.
#
# Usage (on any machine with curl + python3, typically the VM):
#   ./scripts/mint-b2-append-key.sh
# Afterwards: store the printed key in the password manager, configure rclone,
# then consider deleting/regenerating the master key exposure surface.
set -euo pipefail

command -v curl >/dev/null || { echo "ERROR: curl required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 required" >&2; exit 1; }

read -rp  "B2 master keyID (from App Keys page): " MASTER_KEY_ID
read -rsp "B2 master application key (input hidden): " MASTER_KEY; echo
read -rp  "Bucket name (e.g. fireplace-backups): " BUCKET_NAME
read -rp  "New key name [fireplace-vps-append]: " KEY_NAME
KEY_NAME="${KEY_NAME:-fireplace-vps-append}"

json() { python3 -c "import sys,json;print(json.load(sys.stdin)$1)"; }

echo "==> authorizing"
AUTH="$(curl -fsS -u "$MASTER_KEY_ID:$MASTER_KEY" \
  https://api.backblazeb2.com/b2api/v2/b2_authorize_account)"
API_URL="$(echo "$AUTH" | json "['apiUrl']")"
TOKEN="$(echo "$AUTH" | json "['authorizationToken']")"
ACCOUNT_ID="$(echo "$AUTH" | json "['accountId']")"

echo "==> resolving bucket id for $BUCKET_NAME"
BUCKET_ID="$(curl -fsS -H "Authorization: $TOKEN" \
  -d "{\"accountId\":\"$ACCOUNT_ID\",\"bucketName\":\"$BUCKET_NAME\"}" \
  "$API_URL/b2api/v2/b2_list_buckets" | json "['buckets'][0]['bucketId']")"

echo "==> creating append-only key '$KEY_NAME' (listBuckets, listFiles, readFiles, writeFiles — NO deleteFiles)"
RESULT="$(curl -fsS -H "Authorization: $TOKEN" \
  -d "{\"accountId\":\"$ACCOUNT_ID\",\"keyName\":\"$KEY_NAME\",\"bucketId\":\"$BUCKET_ID\",\"capabilities\":[\"listBuckets\",\"listFiles\",\"readFiles\",\"writeFiles\"]}" \
  "$API_URL/b2api/v2/b2_create_key")"

APP_KEY_ID="$(echo "$RESULT" | json "['applicationKeyId']")"
APP_KEY="$(echo "$RESULT" | json "['applicationKey']")"

cat <<EOF

============================================================
NEW KEY (shown ONCE — store BOTH values in the password manager NOW):
  applicationKeyId: $APP_KEY_ID
  applicationKey:   $APP_KEY

rclone setup on the VM:
  rclone config create fireplace-b2 b2 account "$APP_KEY_ID" key "<applicationKey>"
  chmod 600 ~/.config/rclone/rclone.conf
  rclone lsd fireplace-b2:      # should list: $BUCKET_NAME
============================================================
EOF
