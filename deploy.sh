#!/usr/bin/env bash
# Production deploy helper for Fireplace VM (copy to ~/deploy.sh or run from repo root).
# Injects git commit + build timestamp into backend env and Flutter web build.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$REPO_DIR"

git pull

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
# Semver only for API/UI (strip +build from pubspec if present)
APP_VERSION="$(grep '^version:' frontend/pubspec.yaml | sed 's/version: //' | tr -d ' ' | cut -d'+' -f1)"

export GIT_COMMIT
export BUILD_TIME
export APP_VERSION

# PWA push subscribe must use the same VAPID public key as backend (.env).
if [[ -z "${WEB_PUSH_VAPID_PUBLIC_KEY:-}" && -f "$REPO_DIR/.env" ]]; then
  WEB_PUSH_VAPID_PUBLIC_KEY="$(
    grep -E '^WEB_PUSH_VAPID_PUBLIC_KEY=' "$REPO_DIR/.env" \
      | head -1 \
      | cut -d= -f2- \
      | tr -d '\r' \
      | sed 's/^["'\''"]//;s/["'\''"]$//'
  )"
  export WEB_PUSH_VAPID_PUBLIC_KEY
fi
if [[ -z "${WEB_PUSH_VAPID_PUBLIC_KEY:-}" ]]; then
  echo "ERROR: WEB_PUSH_VAPID_PUBLIC_KEY missing — set in ~/fireplace/.env or export before deploy." >&2
  exit 1
fi

echo "Deploying Fireplace: version=${APP_VERSION} commit=${GIT_COMMIT} built=${BUILD_TIME}"
echo "Web Push VAPID public key prefix: ${WEB_PUSH_VAPID_PUBLIC_KEY:0:20}..."

docker compose build --build-arg GIT_COMMIT="$GIT_COMMIT" \
  --build-arg BUILD_TIME="$BUILD_TIME" \
  --build-arg APP_VERSION="$APP_VERSION" \
  backend 2>/dev/null || docker-compose build backend

docker compose up -d backend 2>/dev/null || docker-compose up -d backend

cd frontend
flutter pub get
flutter build web --release \
  --dart-define=BASE_URL="${BASE_URL:-https://fireplace.ignorelist.com}" \
  --dart-define=GIT_COMMIT="$GIT_COMMIT" \
  --dart-define=BUILD_TIME="$BUILD_TIME" \
  --dart-define=WEB_PUSH_VAPID_PUBLIC_KEY="$WEB_PUSH_VAPID_PUBLIC_KEY"

echo "Flutter web build complete. Reload nginx / copy build/web to your web root per your VM setup."
