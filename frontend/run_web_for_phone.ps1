# Run Flutter web so you can open the app on your phone's browser.
# 1. Backend must be running (docker-compose up) and reachable at $HostIP:3000
# 2. On phone (same WiFi): open http://$HostIP:8080
# Use web-server (not chrome): -d chrome with 0.0.0.0 causes "AppConnectionException" (DWDS WebSocket fails).
# If page does not load: allow "Dart" or "Flutter" in Windows Firewall when prompted, or allow port 8080.

$HostIP = "192.168.1.11"
Set-Location $PSScriptRoot
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=BASE_URL=http://${HostIP}:3000
