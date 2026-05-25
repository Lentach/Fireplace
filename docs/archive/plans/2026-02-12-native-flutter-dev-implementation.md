# Native Flutter Dev Workflow - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate from Docker-based Flutter web development to native Flutter development with instant hot-reload, reducing Docker image footprint from 7GB to ~400MB.

**Architecture:** Remove frontend from Docker, keep only backend + DB. Frontend runs natively via `flutter run` for instant hot-reload. Optional web preview via separate docker-compose file.

**Tech Stack:** Docker Compose, NestJS (backend), Flutter (native mobile), PostgreSQL

---

## Task 1: Backup Current State

**Files:**
- Modify: `.git/` (via git commit)

**Step 1: Check git status**

Run: `git status`
Expected: Shows modified/untracked files

**Step 2: Commit current state as backup**

```bash
git add -A
git commit -m "backup: before migration to native Flutter dev

Current state: Docker-based Flutter web with 7GB frontend image.
About to migrate to native Flutter dev workflow.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created successfully

**Step 3: Verify commit**

Run: `git log --oneline -1`
Expected: Shows "backup: before migration to native Flutter dev"

---

## Task 2: Remove Obsolete Frontend Docker Files

**Files:**
- Delete: `frontend/Dockerfile.dev`
- Delete: `frontend/dev-entrypoint.sh`

**Step 1: Verify files exist**

Run: `ls frontend/Dockerfile.dev frontend/dev-entrypoint.sh`
Expected: Both files listed

**Step 2: Remove Dockerfile.dev**

```bash
rm frontend/Dockerfile.dev
```

Expected: File deleted

**Step 3: Remove dev-entrypoint.sh**

```bash
rm frontend/dev-entrypoint.sh
```

Expected: File deleted

**Step 4: Verify removal**

Run: `ls frontend/Dockerfile.dev frontend/dev-entrypoint.sh`
Expected: "No such file or directory" error

**Step 5: Commit removal**

```bash
git add -A
git commit -m "chore: remove obsolete Docker dev files for frontend

Removed:
- frontend/Dockerfile.dev (replaced by native flutter run)
- frontend/dev-entrypoint.sh (polling watcher no longer needed)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created

---

## Task 3: Rewrite docker-compose.yml (Backend + DB Only)

**Files:**
- Modify: `docker-compose.yml` (rewrite entire file)

**Step 1: Read current docker-compose.yml**

Use Read tool on: `docker-compose.yml`
Expected: See current configuration with frontend service

**Step 2: Backup current content**

Note: Already done in Task 1 git commit

**Step 3: Write new docker-compose.yml**

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

**Step 4: Verify syntax**

Run: `docker-compose config`
Expected: No errors, prints parsed config

**Step 5: Commit changes**

```bash
git add docker-compose.yml
git commit -m "refactor: simplify docker-compose to backend + DB only

Removed frontend service from docker-compose.yml.
Frontend now runs natively via flutter run for instant hot-reload.

Changes:
- Removed frontend service
- Backend uses Dockerfile (multi-stage, optimized)
- Volume mount for backend hot-reload
- Command override: npm run start:dev

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created

---

## Task 4: Create docker-compose.web.yml (Optional Web Preview)

**Files:**
- Create: `docker-compose.web.yml`

**Step 1: Create docker-compose.web.yml**

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

**Step 2: Verify syntax**

Run: `docker-compose -f docker-compose.web.yml config`
Expected: No errors, prints parsed config with extended services

**Step 3: Commit new file**

```bash
git add docker-compose.web.yml
git commit -m "feat: add optional web preview docker-compose

Created docker-compose.web.yml for optional web testing.
Extends main docker-compose.yml and adds frontend service.

Usage: docker-compose -f docker-compose.web.yml up

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created

---

## Task 5: Update CLAUDE.md Section 2 (Quick Start)

**Files:**
- Modify: `CLAUDE.md:25-39` (section 2)

**Step 1: Read current section 2**

Use Read tool on: `CLAUDE.md` (lines 25-39)
Expected: See old Quick Start instructions

**Step 2: Replace section 2**

Old content (lines 25-39):
```markdown
## 2. Quick Start

**Stack:** NestJS + Flutter + PostgreSQL + Socket.IO + JWT. 1-on-1 chat.

**Structure:** `backend/` :3000, `frontend/` :8080 (nginx in Docker). Manual E2E scripts in `scripts/` (see `scripts/README.md`).

**Run:**
```bash
# .env: CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
docker-compose up --build
```

**Before run:** `tasklist | findstr node` → kill if needed. One backend only.

**Frontend config:** `BASE_URL` dart define (default localhost:3000). JWT stored in SharedPreferences (`jwt_token`).
```

New content:
```markdown
## 2. Quick Start

**Stack:** NestJS + Flutter + PostgreSQL + Socket.IO + JWT. Mobile-first, web optional.

**Structure:** `backend/` :3000, `frontend/` Flutter app (run locally or build for web :8080). Manual E2E scripts in `scripts/` (see `scripts/README.md`).

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

**Step 3: Update CLAUDE.md header (Last updated)**

Change line 2:
```markdown
**Last updated:** 2026-02-12
```

**Step 4: Commit changes**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md Quick Start for native Flutter workflow

Updated section 2 with new development workflow:
- Start backend + DB via docker-compose
- Run Flutter natively for instant hot-reload
- Optional web preview via docker-compose.web.yml

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created

---

## Task 6: Update README.md

**Files:**
- Modify: `README.md:21-36` (Quick Start section)
- Modify: `README.md:63-73` (Frontend local run section)

**Step 1: Read current Quick Start section**

Use Read tool on: `README.md` (lines 21-36)
Expected: See Docker-only instructions

**Step 2: Update Quick Start section**

Old content (lines 21-36):
```markdown
## Quick Start (Docker)

> Requirements: [Docker](https://docs.docker.com/get-docker/) and Docker Compose

```bash
# 1. Clone the repository
git clone https://github.com/Lentach/mvp-chat-app.git
cd mvp-chat-app

# 2. Build and run
docker-compose up --build
```

- **Frontend:** http://localhost:8080
- **Backend API:** http://localhost:3000
```

New content:
```markdown
## Quick Start (Mobile Development)

> Requirements: [Flutter SDK](https://flutter.dev/docs/get-started/install), [Docker](https://docs.docker.com/get-docker/)

```bash
# 1. Clone the repository
git clone https://github.com/Lentach/mvp-chat-app.git
cd mvp-chat-app

# 2. Start backend + database
docker-compose up

# 3. In another terminal: Run Flutter on your device
cd frontend
flutter devices              # List available devices
flutter run -d <device-id>   # Hot-reload enabled
```

- **Backend API:** http://192.168.1.11:3000 (accessible from phone)
- **Frontend:** Native Flutter app with instant hot-reload

**Optional - Web Preview:**
```bash
docker-compose -f docker-compose.web.yml up --build
```
- **Frontend (web):** http://localhost:8080
```

**Step 3: Update Frontend local run section**

Old content (lines 63-73):
```markdown
### Frontend

```bash
cd frontend

# 1. Install dependencies
flutter pub get

# 2. Run in Chrome (connects to backend on localhost:3000)
flutter run -d chrome
```
```

New content:
```markdown
### Frontend

**Mobile (Recommended):**
```bash
cd frontend

# 1. Install dependencies
flutter pub get

# 2. Connect device via USB or WiFi
flutter devices

# 3. Run on device
flutter run -d <device-id> --dart-define=BASE_URL=http://192.168.1.11:3000
```

**Web (Optional):**
```bash
cd frontend
flutter run -d chrome --dart-define=BASE_URL=http://localhost:3000
```
```

**Step 4: Commit changes**

```bash
git add README.md
git commit -m "docs: update README for native Flutter development

Updated Quick Start and Frontend sections:
- Primary workflow: Flutter native on mobile device
- Optional: Web preview via docker-compose.web.yml
- Added instructions for flutter devices and hot-reload

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit created

---

## Task 7: Test Backend + DB Startup

**Files:**
- None (verification only)

**Step 1: Stop any running Docker containers**

```bash
docker-compose down
```

Expected: Containers stopped (or "no containers" if none running)

**Step 2: Kill existing node processes**

```bash
taskkill //F //IM node.exe
```

Expected: Node processes terminated (or "not found" if none running)

**Step 3: Start backend + DB**

```bash
docker-compose up --build
```

Expected:
- PostgreSQL starts on port 5433
- Backend builds and starts on port 3000
- No frontend container
- Logs show "Server running on http://0.0.0.0:3000"

**Step 4: Verify backend is accessible**

In another terminal:
```bash
curl http://localhost:3000
```

Expected: Response (e.g., "Cannot GET /" or similar - not connection error)

**Step 5: Stop containers**

Press `Ctrl+C` in docker-compose terminal, then:
```bash
docker-compose down
```

Expected: Containers stopped cleanly

---

## Task 8: Test Flutter Native Run (if device available)

**Files:**
- None (verification only)

**Note:** This task requires a physical device or emulator. Skip if not available.

**Step 1: Start backend + DB**

```bash
docker-compose up
```

Expected: Backend running on port 3000

**Step 2: Check available Flutter devices**

In another terminal:
```bash
cd frontend
flutter devices
```

Expected: List of available devices (phone, emulator, or "No devices detected")

**Step 3: Run Flutter on device (if available)**

```bash
flutter run -d <device-id> --dart-define=BASE_URL=http://192.168.1.11:3000
```

Replace `192.168.1.11` with your computer's local IP.
Replace `<device-id>` with actual device ID from step 2.

Expected:
- App builds and launches on device
- Connects to backend
- Hot-reload enabled (press 'r' to test)

**Step 4: Test hot-reload**

1. Make a small change in `frontend/lib/main.dart` (e.g., change a text string)
2. Save the file
3. Press 'r' in the flutter run terminal

Expected: App reloads instantly without full rebuild

**Step 5: Stop Flutter**

Press 'q' in flutter run terminal

Expected: App stops, terminal returns to prompt

**Step 6: Stop backend**

```bash
docker-compose down
```

Expected: Containers stopped

---

## Task 9: Test Optional Web Preview

**Files:**
- None (verification only)

**Step 1: Start web preview**

```bash
docker-compose -f docker-compose.web.yml up --build
```

Expected:
- DB starts
- Backend starts on port 3000
- Frontend builds (Flutter web) and starts on port 8080
- Logs show nginx serving frontend

**Step 2: Verify frontend is accessible**

Open browser: `http://localhost:8080`

Expected: Flutter web app loads

**Step 3: Stop containers**

Press `Ctrl+C`, then:
```bash
docker-compose -f docker-compose.web.yml down
```

Expected: All containers stopped

---

## Task 10: Cleanup Old Docker Images

**Files:**
- None (Docker images cleanup)

**Step 1: List current Docker images**

```bash
docker images | findstr "mvp-chat-app"
```

Expected: Shows mvp-chat-app images with sizes

**Step 2: Check image sizes before cleanup**

Note the sizes (should show old 7GB frontend if still present)

**Step 3: Remove all unused Docker images**

```bash
docker system prune -a
```

When prompted, type 'y' to confirm.

Expected: Old images removed, including 7GB frontend

**Step 4: Verify image sizes after cleanup**

```bash
docker-compose up --build
```

Then in another terminal:
```bash
docker images | findstr "mvp-chat-app"
```

Expected:
- Backend image: ~357-644 MB (depends on build stage caching)
- No frontend image listed (only built when using docker-compose.web.yml)

**Step 5: Stop containers**

```bash
docker-compose down
```

Expected: Containers stopped

---

## Task 11: Update MEMORY.md with New Startup Commands

**Files:**
- Modify: `C:\Users\Lentach\.claude\projects\C--Users-Lentach-desktop-mvp-chat-app\memory\MEMORY.md`

**Step 1: Read current MEMORY.md**

Use Read tool on: `C:\Users\Lentach\.claude\projects\C--Users-Lentach-desktop-mvp-chat-app\memory\MEMORY.md`

**Step 2: Add new section after "Project Quick Ref"**

Add after line 7:

```markdown
## Startup Commands (2026-02-12)

**Mobile development (recommended):**
```bash
# Terminal 1: Backend + DB
docker-compose up

# Terminal 2: Flutter on device
cd frontend
flutter devices
flutter run -d <device-id>
```

**Web preview (optional):**
```bash
docker-compose -f docker-compose.web.yml up --build
# Frontend: http://localhost:8080
```

**Before start:**
- Kill node: `taskkill //F //IM node.exe`
- Same WiFi: phone + computer
- Update IP in BASE_URL if needed
```

**Step 3: Write updated MEMORY.md**

Use Write or Edit tool to update the file.

Expected: Section added successfully

---

## Task 12: Final Commit and Summary

**Files:**
- Modify: `.git/` (via git commit)

**Step 1: Check git status**

```bash
git status
```

Expected: All changes committed (clean working tree)

**Step 2: Create final migration commit (if any uncommitted changes)**

```bash
git add -A
git commit -m "feat: complete migration to native Flutter dev workflow

Migration complete:
- Frontend: Native Flutter run (instant hot-reload)
- Backend: Docker with volume mount (NestJS hot-reload)
- Docker footprint: 7GB → ~400MB
- Web preview: Optional via docker-compose.web.yml

Updated:
- docker-compose.yml (backend + DB only)
- docker-compose.web.yml (optional web)
- CLAUDE.md section 2 (Quick Start)
- README.md (Quick Start, Frontend sections)
- MEMORY.md (startup commands)

Removed:
- frontend/Dockerfile.dev
- frontend/dev-entrypoint.sh

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Final commit created (or "nothing to commit" if already done)

**Step 3: View commit history**

```bash
git log --oneline -8
```

Expected: Shows all migration commits in order

**Step 4: Push to remote (optional)**

If user wants to push:
```bash
git push origin master
```

Expected: Commits pushed to GitHub

---

## Verification Checklist

After completing all tasks, verify:

- [ ] `docker-compose up` starts only backend + DB (no frontend)
- [ ] Backend accessible at http://localhost:3000
- [ ] `flutter run -d <device>` launches app on phone (if device available)
- [ ] Hot-reload works (press 'r' after code change)
- [ ] `docker-compose -f docker-compose.web.yml up` builds web frontend
- [ ] Web frontend accessible at http://localhost:8080
- [ ] Docker images reduced from 7GB to ~400MB
- [ ] All commits pushed to git
- [ ] CLAUDE.md updated with new workflow
- [ ] README.md updated with new instructions
- [ ] MEMORY.md updated with startup commands

---

## Rollback Plan

If migration fails, rollback:

```bash
# Find the backup commit
git log --oneline | grep "backup: before migration"

# Reset to backup commit
git reset --hard <backup-commit-hash>

# Restart old workflow
docker-compose up --build
```

---

**Implementation complete! 🎉**

**Next steps:**
- Test on real device with `flutter run`
- Verify hot-reload speed improvement
- Update team documentation if needed
- Consider removing web support entirely if not needed
