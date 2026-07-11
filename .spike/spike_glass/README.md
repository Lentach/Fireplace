# spike_glass — Liquid Glass perf harness (throwaway, not shipped)

Reproduces the measurements in `docs/design/liquid-glass/SPIKE.md`.

Only `lib/`, `pubspec.yaml`, `pubspec.lock`, and this README are tracked; platform
scaffolding and build output are not. To run:

```powershell
cd .spike/spike_glass
flutter create --platforms web,android --project-name spike_glass .
flutter pub get

# Web (shipping renderer): build release, serve, open — results in document.title
# AND in the on-screen overlay (usable from a phone on the same LAN).
flutter build web --release --no-wasm-dry-run --pwa-strategy=none
cd build/web ; python -m http.server 8123

# Android (functional smoke): prints SPIKE_RESULT/SPIKE_DONE to flutter run output.
flutter run -d <deviceId> --profile
```

- `lib/main.dart` — self-driving benchmark, modes: baseline | hand | hand5 | pkg | fake; `?mode=<name>` pins a mode for visual inspection without benchmarking.
- `lib/repro.dart` — minimal correct-API `liquid_glass_widgets` composition (bounded pill over labeled grid): `flutter build web --release -t lib/repro.dart -o build/web_repro`.
