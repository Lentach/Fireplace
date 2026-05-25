# Native Flutter Development Setup - Design Document

**Date:** 2026-02-12
**Status:** Approved
**Goal:** Migrate from Docker-based Flutter web development to native Flutter development with instant hot-reload

---

## Problem Statement

Current issues:
- Frontend Docker image bloated to 7.02 GB (should be ~136 MB)
- Backend Docker image at 644 MB (should be ~357 MB)
- Hot-reload uses slow polling watcher (3s + full rebuild)
- No true instant hot-reload experience
- App is mobile-first, web may be deprecated later

## Solution: Flutter Native + Docker Backend Only

### Architecture

**Two docker-compose files:**

1. **`docker-compose.yml`** (main - backend + DB only)
   - Backend + PostgreSQL services
   - Uses optimized multi-stage Dockerfiles
   - Default: `docker-compose up`
   - Backend listens on `0.0.0.0:3000` (accessible from phone)

2. **`docker-compose.web.yml`** (optional - web preview)
   - Backend + DB + Frontend web services
   - Used only when web preview needed
   - Usage: `docker-compose -f docker-compose.web.yml up`
   - Frontend optimized (~136 MB final image)

### Development Workflow

```bash
# Terminal 1: Start backend + DB
docker-compose up

# Terminal 2: Flutter on device (instant hot-reload)
cd frontend
flutter run -d <device-id>
```

### Communication Flow

- Backend in Docker: `http://192.168.1.11:3000` (local network IP)
- Flutter app: connects via `BASE_URL` (dart-define or hardcoded)
- Phone on same WiFi network as computer
- Hot-reload works instantly (Flutter DevTools enabled)

### Image Optimizations

- Backend: Multi-stage `Dockerfile` → ~357 MB
- Frontend web (optional): Multi-stage `Dockerfile` → ~136 MB
- **Remove:** `Dockerfile.dev`, `dev-entrypoint.sh` (obsolete)
- **Result:** Main development uses 0 MB for frontend (runs natively)

---

## Configuration Details

### docker-compose.yml (Main)

```yaml
# docker-compose.yml — Backend + DB only (for mobile dev)
# Frontend runs locally via: cd frontend && flutter run

services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: chatdb
    ports:
      - '5433:5432'
    volumes:
      - pgdata:/var/lib/postgresql/data

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - '3000:3000'
    environment:
      DB_HOST: db
      DB_PORT: '5432'
      DB_USER: postgres
      DB_PASS: postgres
      DB_NAME: chatdb
      JWT_SECRET: my-super-secret-jwt-key-change-in-production
      ALLOWED_ORIGINS: 'http://localhost:3000,http://192.168.1.11:3000,http://192.168.1.11:8080'
      CLOUDINARY_CLOUD_NAME: ${CLOUDINARY_CLOUD_NAME}
      CLOUDINARY_API_KEY: ${CLOUDINARY_API_KEY}
      CLOUDINARY_API_SECRET: ${CLOUDINARY_API_SECRET}
    depends_on:
      - db
    volumes:
      - ./backend:/app
      - /app/node_modules
    command: npm run start:dev

volumes:
  pgdata:
```

**Key changes:**
- Removed `frontend` service
- Backend uses production `Dockerfile` (multi-stage)
- Volume mount enables backend hot-reload
- Command override: `npm run start:dev` (NestJS watch mode)

### docker-compose.web.yml (Optional)

```yaml
# docker-compose.web.yml — Full stack with web frontend
# Use when you need web preview: docker-compose -f docker-compose.web.yml up

services:
  db:
    extends:
      file: docker-compose.yml
      service: db

  backend:
    extends:
      file: docker-compose.yml
      service: backend

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        BASE_URL: http://192.168.1.11:3000
    ports:
      - '8080:80'
    depends_on:
      - backend
```

**When to use:**
- Web preview needed
- Testing web-specific features
- Pre-deployment verification (prod build check)

---

## Migration Steps

### Files to Remove

```
❌ frontend/Dockerfile.dev
❌ frontend/dev-entrypoint.sh
```

### Files to Modify

- `docker-compose.yml` → rewritten (backend + DB only)
- `CLAUDE.md` section 2 → new Quick Start instructions
- `README.md` (if exists) → update workflow instructions

### Files to Create

- `docker-compose.web.yml` → optional web preview
- `docs/plans/2026-02-12-native-flutter-dev-design.md` → this document

### Existing Files (No Changes)

- `backend/Dockerfile` → already optimized (multi-stage)
- `frontend/Dockerfile` → already optimized (multi-stage)
- `backend/.dockerignore` → already configured
- `frontend/.dockerignore` → already configured

### Migration Procedure

1. **Backup:** Commit current state
   ```bash
   git add -A
   git commit -m "backup: before migration to native Flutter dev"
   ```

2. **Remove obsolete files:**
   ```bash
   rm frontend/Dockerfile.dev
   rm frontend/dev-entrypoint.sh
   ```

3. **Update docker-compose.yml:** Rewrite to backend + DB only

4. **Create docker-compose.web.yml:** Optional web preview config

5. **Update CLAUDE.md:** Section 2 (Quick Start)

6. **Test workflow:**
   ```bash
   # Kill old processes
   taskkill //F //IM node.exe

   # Start backend
   docker-compose up

   # In another terminal: Flutter on device
   cd frontend
   flutter devices
   flutter run -d <device-id>

   # Verify hot-reload (press 'r' after code change)
   ```

7. **Cleanup old images:**
   ```bash
   docker system prune -a
   # This removes the old 7GB frontend image
   ```

8. **Commit migration:**
   ```bash
   git add -A
   git commit -m "feat: migrate to native Flutter dev workflow with instant hot-reload"
   ```

---

## Flutter Configuration

### BASE_URL Setup

**Option 1: Dart-define (recommended for dev)**
```bash
flutter run -d <device> --dart-define=BASE_URL=http://192.168.1.11:3000
```

**Option 2: Hardcoded default (faster, update before prod)**
```dart
// lib/constants/app_constants.dart
class AppConstants {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://192.168.1.11:3000', // Your local IP
  );
}
```

**Option 3: Environment-aware config (best for multiple environments)**
```dart
// lib/config/env_config.dart
class EnvConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  static const String _defaultBaseUrl =
    kDebugMode ? 'http://192.168.1.11:3000' : 'https://api.prod.com';
}
```

### Flutter Devices Setup

**USB (Android):**
```bash
# Enable USB debugging on phone (Settings → Developer Options)
flutter devices
# Output: adb-<serial> • <model> • android-arm64 • Android X.X
flutter run -d adb-<serial>
```

**WiFi (Android - faster after initial setup):**
```bash
# First time (via USB):
adb tcpip 5555
adb connect 192.168.1.X:5555  # Phone IP

# Then always:
flutter devices
# Output: 192.168.1.X:5555 • <model> • android-arm64 • Android X.X
flutter run -d 192.168.1.X:5555
```

**iOS (WiFi):**
- Xcode → Window → Devices & Simulators
- Select device → Check "Connect via network"
- `flutter devices` → auto-discovers

### Hot-Reload Commands

During `flutter run` session:
- **`r`** - Hot reload (instant, preserves state)
- **`R`** - Hot restart (full restart, clears state)
- **`q`** - Quit
- **`h`** - Help (all commands)

---

## Troubleshooting

### "Cannot connect to backend"

```bash
# Check computer IP:
ipconfig  # Windows → IPv4 Address (192.168.1.X)
ip addr   # Linux

# Update BASE_URL with correct IP
# Verify firewall allows port 3000
```

### "Flutter devices empty"

```bash
# Android:
flutter doctor    # Check Android SDK setup
adb devices       # List connected devices

# iOS:
flutter doctor    # Check Xcode setup
```

### "Hot-reload doesn't work"

```bash
# Clean and restart:
flutter clean
flutter pub get
flutter run -d <device>

# Ensure .dart files are saved (auto-reload on save)
```

### "Backend unreachable from phone"

```bash
# 1. Verify backend listens on 0.0.0.0 (not 127.0.0.1)
# backend/src/main.ts should have:
# await app.listen(3000, '0.0.0.0');

# 2. Verify phone on same WiFi network

# 3. Test connection from phone browser:
# http://192.168.1.11:3000 → should return response
```

### Cleanup Old Docker Images

```bash
# List images:
docker images

# Remove old 7GB image:
docker rmi mvp-chat-app-frontend:latest
docker rmi ghcr.io/cirruslabs/flutter:latest

# Or cleanup everything:
docker system prune -a --volumes
# Then rebuild: docker-compose up --build
```

---

## Benefits Summary

### Development Experience
- ⚡ **Instant hot-reload** (no rebuild wait)
- 🎯 **Native mobile testing** (exact production environment)
- 🔧 **Full Flutter DevTools** (debugger, inspector, profiler)
- 📱 **USB or WiFi** debugging (flexible setup)

### Performance
- 🪶 **No frontend Docker overhead** (0 MB vs 7 GB)
- 🚀 **Faster iteration** (seconds vs minutes)
- 💾 **Reduced disk usage** (~400 MB total vs ~7.6 GB)

### Architecture
- 🎨 **Mobile-first** (aligns with product direction)
- 🌐 **Web optional** (easy to enable when needed)
- 🐳 **Simplified Docker** (only what needs containerization)

---

## CLAUDE.md Updates

Section 2 (Quick Start) will be updated to:

```markdown
## 2. Quick Start

**Stack:** NestJS + Flutter + PostgreSQL + Socket.IO + JWT. Mobile-first, web optional.

**Structure:** `backend/` :3000, `frontend/` Flutter app (run locally or build for web :8080)

**Development workflow:**

1. **Start backend + DB** (always):
   ```bash
   docker-compose up
   ```
   Backend: http://192.168.1.11:3000 (accessible from phone)

2. **Run Flutter on device** (mobile dev - recommended):
   ```bash
   cd frontend
   flutter devices  # List available devices
   flutter run -d <device-id>  # Hot-reload enabled
   ```

3. **Or run web build** (optional, for web testing):
   ```bash
   docker-compose -f docker-compose.web.yml up --build
   ```
   Frontend: http://192.168.1.11:8080

**Before run:**
- Kill existing node processes: `taskkill //F //IM node.exe`
- Ensure phone/computer on same WiFi network
- Update `BASE_URL` in flutter run: `--dart-define=BASE_URL=http://192.168.1.11:3000`

**Frontend config:** `BASE_URL` via dart-define or hardcoded default. JWT stored in SharedPreferences (`jwt_token`).
```

---

## Implementation Checklist

- [ ] Backup current state (git commit)
- [ ] Remove `frontend/Dockerfile.dev`
- [ ] Remove `frontend/dev-entrypoint.sh`
- [ ] Rewrite `docker-compose.yml` (backend + DB only)
- [ ] Create `docker-compose.web.yml` (optional web)
- [ ] Update `CLAUDE.md` section 2
- [ ] Update `README.md` (if exists)
- [ ] Test: `docker-compose up` → backend starts
- [ ] Test: `flutter run -d <device>` → app on phone
- [ ] Verify: hot-reload works (press 'r')
- [ ] Cleanup: `docker system prune -a` (remove 7GB image)
- [ ] Commit: migration complete
- [ ] Update `MEMORY.md` with new startup commands

---

**Next Steps:** Proceed to implementation using git worktree + detailed plan.
