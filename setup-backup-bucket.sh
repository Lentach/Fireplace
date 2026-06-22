#!/usr/bin/env bash
# One-time: create a PRIVATE GCS bucket for Fireplace backups (+ lifecycle + IAM).
#
# The bucket is private (uniform bucket-level access + public-access prevention).
# Objects auto-delete after LIFECYCLE_DAYS (independent of the backup script's local
# RETENTION_DAYS — offsite intentionally keeps history longer). Run on a machine with
# gcloud authenticated and permission on the project (e.g. your PC or the VM).
#
# Usage:
#   BUCKET=gs://fireplace-backups-xyz PROJECT=my-gcp-project \
#   [LOCATION=europe-central2] [LIFECYCLE_DAYS=30] \
#   [SA=vm-service-account@my-gcp-project.iam.gserviceaccount.com] \
#   ./setup-backup-bucket.sh
set -euo pipefail

: "${BUCKET:?set BUCKET=gs://your-bucket}"
: "${PROJECT:?set PROJECT=your-gcp-project}"
LOCATION="${LOCATION:-europe-central2}"
LIFECYCLE_DAYS="${LIFECYCLE_DAYS:-30}"

echo "==> creating $BUCKET (private) in $LOCATION"
gcloud storage buckets create "$BUCKET" \
  --project "$PROJECT" --location "$LOCATION" \
  --uniform-bucket-level-access --public-access-prevention \
  || echo "   (bucket may already exist — continuing)"

echo "==> applying lifecycle: delete objects older than ${LIFECYCLE_DAYS}d"
lc="$(mktemp)"; trap 'rm -f "$lc"' EXIT
printf '{"rule":[{"action":{"type":"Delete"},"condition":{"age":%s}}]}\n' "$LIFECYCLE_DAYS" > "$lc"
gcloud storage buckets update "$BUCKET" --lifecycle-file="$lc"

if [[ -n "${SA:-}" ]]; then
  echo "==> granting roles/storage.objectAdmin to $SA"
  gcloud storage buckets add-iam-policy-binding "$BUCKET" \
    --member="serviceAccount:$SA" --role="roles/storage.objectAdmin"
fi

echo "Done. In the backup cron set:  BACKUP_GCS_BUCKET=$BUCKET"
echo "Smoke test write access:  echo hi | gsutil cp - $BUCKET/_writetest && gsutil rm $BUCKET/_writetest"
