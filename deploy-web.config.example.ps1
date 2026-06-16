# Template for deploy-web.ps1's per-machine settings.
# Copy this file to  deploy-web.config.ps1  (gitignored) and fill in YOUR values.
# Nothing here is committed to the public repo.

# --- Method A (recommended for a GCP VM): Google Cloud CLI ---
# Install: https://cloud.google.com/sdk/docs/install ; then `gcloud auth login`.
# Find the instance + zone: `gcloud compute instances list`.
# IMPORTANT: GcloudUser is the LOGIN USER ON THE VM that owns the repo (e.g. olek292) -
# NOT your local Windows username. gcloud connects as your Windows user by default,
# which lands in the wrong home, so set this explicitly.
$GcloudUser     = "olek292"
$GcloudInstance = "fireplace-server"
$GcloudZone     = "europe-central2-a"

# --- Method B (fallback): plain ssh/scp to the EXTERNAL IP (needs SSH-key access) ---
# Leave the gcloud lines above blank and set:
# $VmSshTarget = "olek292@<external-ip>"

# Repo directory on the VM, relative to that user's home (~):
$RemoteDir = "fireplace"
