#!/usr/bin/env bash
# Production deploy helper for Fireplace VM (copy to ~/deploy.sh or run from repo root).
# Injects git commit + build timestamp into backend env and Flutter web build.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$REPO_DIR"

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
APP_VERSION="$(grep '^version:' frontend/pubspec.yaml | sed 's/version: //' | tr -d ' ')"

export GIT_COMMIT
export BUILD_TIME
export APP_VERSION

echo "Deploying Fireplace: version=${APP_VERSION} commit=${GIT_COMMIT} built=${BUILD_TIME}"

git pull

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
  --dart-define=BUILD_TIME="$BUILD_TIME"

echo "Flutter web build complete. Reload nginx / copy build/web to your web root per your VM setup."
