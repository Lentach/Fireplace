#!/usr/bin/env bash
# DEPRECATED / DISABLED — do not use.
#
# This legacy all-in-one script selected the DEV docker-compose (it ran
# `docker compose up -d backend` with no `-f docker-compose.prod.yml`), which on
# the VM would start the backend in dev mode with TypeORM auto-DDL against the
# LIVE PRODUCTION DATABASE, and it built the Flutter web bundle on the
# memory-starved VM (dart2js OOM). It also predates the OVH migration — the old
# GCP VM referenced by the original flow is decommissioned.
#
# Use the split deploy instead:
#   Backend  (on the VM):  cd ~/fireplace && ./deploy-backend.sh
#   Frontend (on your PC): git pull ; .\deploy-web.ps1
# See CLAUDE.md §4 and .cursor/rules/production-vm-deploy.mdc.

echo "deploy.sh is disabled. Use ./deploy-backend.sh (VM) + deploy-web.ps1 (PC). See CLAUDE.md §4." >&2
exit 1
