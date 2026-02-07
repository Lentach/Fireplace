#!/bin/sh
# dev-entrypoint.sh - Flutter web dev server with polling-based change detection
# Needed because Docker volumes on Windows don't propagate inotify events to Linux containers

cd /app

# Content hash of Dart files
get_hash() {
  find /app/lib -name "*.dart" -exec md5sum {} \; 2>/dev/null | sort | md5sum
}

# Create named pipe for Flutter stdin (hot reload commands)
PIPE=/tmp/flutter_stdin
rm -f $PIPE
mkfifo $PIPE

echo "[dev-watch] Starting Flutter web dev server..."
# Keep pipe open in background, redirect to Flutter stdin
(tail -f $PIPE) | flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0 \
  --dart-define=BASE_URL=http://localhost:3000 &
FLUTTER_PID=$!

# Wait for initial compilation
sleep 5

LAST=$(get_hash)
echo "[dev-watch] Polling for file changes every 2s. Hot reload enabled!"

while kill -0 $FLUTTER_PID 2>/dev/null; do
  sleep 2
  NOW=$(get_hash)
  if [ "$NOW" != "$LAST" ]; then
    echo "[dev-watch] File changes detected, sending hot reload command..."
    # Send 'r' (hot reload) to Flutter stdin via named pipe
    echo "r" > $PIPE
    LAST="$NOW"
    echo "[dev-watch] Hot reload triggered!"
  fi
done

echo "[dev-watch] Flutter process exited."
rm -f $PIPE
wait $FLUTTER_PID
