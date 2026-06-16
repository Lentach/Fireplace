# Template for deploy-web.ps1's per-machine settings.
# Copy this file to  deploy-web.config.ps1  (gitignored) and fill in YOUR values.
# Set ONE publish method. Nothing here is committed to the public repo.

# --- Method A (recommended for a GCP VM): Google Cloud CLI ---
# Install: https://cloud.google.com/sdk/docs/install ; then `gcloud auth login`.
# Find your zone: `gcloud compute instances list`.
$GcloudInstance = "fireplace-server"
$GcloudZone     = "europe-central2-a"

# --- Method B (fallback): plain ssh/scp to the VM's EXTERNAL IP (needs SSH-key access) ---
# $VmSshTarget = "olek292@34.118.0.0"

# Repo directory on the VM, relative to the SSH login home (~):
$RemoteDir = "fireplace"
