# Mobile Deployment — Flutter on Physical Device

**Document Version:** 1.0  
**Created:** 2026-02-04  
**Status:** PLANNED (Not Implemented)  
**Author:** Architecture Research Session  

**Source of truth for implementation.** An agent implementing this should read ONLY this file to understand the full scope and execute changes.

**Related plan:** `docs/plans/2026-02-04-mobile-deployment-plan.md` (detailed Polish guide).

---

## Executive Summary

This document describes how to run the Flutter app on a **physical iOS or Android device** in debug mode, with the backend running on the developer's computer in the local WiFi network.

### Key Concepts

| Concept | Meaning |
|--------|---------|
| **BASE_URL** | Full backend URL passed to Flutter at build/run time, e.g. `http://192.168.1.100:3000` |
| **ALLOWED_ORIGINS** | CORS whitelist — client origins the backend accepts. **Does NOT include port.** |
| **Origin** | For mobile apps: often `http://<IP>` (no port) or `null` — NOT the backend URL |
| **usesCleartextTraffic** | Android: allows HTTP (non-HTTPS) connections (required for local dev) |
| **NSAppTransportSecurity** | iOS: allows HTTP connections (required for local dev) |

**Critical:** `BASE_URL` = backend URL **with** port (:3000). `Origin` in ALLOWED_ORIGINS = client address **without** port.

---

## Table of Contents

1. [Current Configuration](#1-current-configuration)
2. [Files to Modify](#2-files-to-modify)
3. [Exact Code Changes](#3-exact-code-changes)
4. [Implementation Procedure](#4-implementation-procedure)
5. [Verification Checklist](#5-verification-checklist)
6. [Troubleshooting](#6-troubleshooting)
7. [Production Next Steps](#7-production-next-steps)
8. [Quick Reference](#8-quick-reference)

---

## 1. Current Configuration

### 1.1 Frontend (Flutter)

| Item | Location | Current Value |
|------|----------|---------------|
| BASE_URL | `frontend/lib/config/app_config.dart` | `String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:3000')` |
| How to pass | CLI | `--dart-define=BASE_URL=...` at `flutter run` |

### 1.2 Backend (NestJS)

| Item | Location | Notes |
|------|----------|-------|
| ALLOWED_ORIGINS (Docker) | `docker-compose.yml` → `backend.environment.ALLOWED_ORIGINS` | **Used when backend runs via Docker** |
| ALLOWED_ORIGINS (local) | `.env` in project root | Used when backend runs via `npm run start:dev` in backend/ |
| Current Docker value | Line 27 | `'http://localhost:3000,http://localhost:8080,http://192.168.1.11:8080'` |

**Rule:** If backend runs in **Docker** → edit `docker-compose.yml`. If backend runs **locally** → edit `.env`.

### 1.3 iOS (`frontend/ios/Runner/Info.plist`)

| Item | Status |
|------|--------|
| NSAppTransportSecurity | **MISSING** — iOS blocks HTTP by default |
| NSCameraUsageDescription | **MISSING** — needed for image_picker (avatar) |
| NSPhotoLibraryUsageDescription | **MISSING** — needed for image_picker |

### 1.4 Android (`frontend/android/app/src/main/AndroidManifest.xml`)

| Item | Status |
|------|--------|
| INTERNET permission | **MISSING** — needed for HTTP/Socket.IO |
| usesCleartextTraffic | **MISSING** — Android 9+ blocks HTTP |
| CAMERA permission | **MISSING** — needed for image_picker |
| READ_EXTERNAL_STORAGE | **MISSING** |
| READ_MEDIA_IMAGES | **MISSING** (Android 13+) |
| WRITE_EXTERNAL_STORAGE | **MISSING** (legacy) |

---

## 2. Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `docker-compose.yml` (or `.env`) | Add IP to ALLOWED_ORIGINS |
| 2 | `frontend/ios/Runner/Info.plist` | Add NSAppTransportSecurity + camera/photo permissions |
| 3 | `frontend/android/app/src/main/AndroidManifest.xml` | Add permissions + usesCleartextTraffic |

**Paths (absolute):**

- `c:\Users\Lentach\Desktop\mvp-chat-app\docker-compose.yml`
- `c:\Users\Lentach\Desktop\mvp-chat-app\frontend\ios\Runner\Info.plist`
- `c:\Users\Lentach\Desktop\mvp-chat-app\frontend\android\app\src\main\AndroidManifest.xml`

---

## 3. Exact Code Changes

### 3.1 Backend CORS — `docker-compose.yml`

**Location:** Line 27, `ALLOWED_ORIGINS`

**Before:**
```yaml
ALLOWED_ORIGINS: 'http://localhost:3000,http://localhost:8080,http://192.168.1.11:8080'
```

**After (example with IP 192.168.1.100):**
```yaml
ALLOWED_ORIGINS: 'http://localhost:3000,http://localhost:8080,http://192.168.1.11:8080,http://192.168.1.100'
```

**Rules:**

- Replace `192.168.1.100` with your computer's IP from `ipconfig` (Windows) or `ifconfig` (Mac/Linux).
- Do **NOT** add `:3000` to the origin. Origin is client address, not backend.
- If CORS error shows `from origin 'null'`, add `,null` to ALLOWED_ORIGINS.
- If CORS error shows another origin, add exactly that string.

**For local backend:** Edit `.env` instead:

```env
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://192.168.1.100
```

---

### 3.2 iOS — `frontend/ios/Runner/Info.plist`

**Location:** Add **before** the closing `</dict>` (before line 47).

**Insert this block:**

```xml
	<!-- Allow HTTP connections to local IP (development only) -->
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<!-- Camera permission for avatar upload -->
	<key>NSCameraUsageDescription</key>
	<string>App needs camera access to update profile picture.</string>
	<!-- Photo library permission for avatar upload -->
	<key>NSPhotoLibraryUsageDescription</key>
	<string>App needs photo library access to choose profile picture.</string>
```

**Full context — BEFORE (last lines):**

```xml
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
</dict>
</plist>
```

**AFTER:**

```xml
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<!-- Allow HTTP connections to local IP (development only) -->
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<!-- Camera permission for avatar upload -->
	<key>NSCameraUsageDescription</key>
	<string>App needs camera access to update profile picture.</string>
	<!-- Photo library permission for avatar upload -->
	<key>NSPhotoLibraryUsageDescription</key>
	<string>App needs photo library access to choose profile picture.</string>
</dict>
</plist>
```

**Production note:** `NSAllowsArbitraryLoads = true` disables ATS. For production, use HTTPS and remove this block.

---

### 3.3 Android — `frontend/android/app/src/main/AndroidManifest.xml`

**Change A:** Add permissions **after** `<manifest>` and **before** `<application>`:

```xml
    <!-- Network access for API + Socket.IO -->
    <uses-permission android:name="android.permission.INTERNET"/>

    <!-- Camera/Photo permissions for avatar upload -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28"/>
```

**Change B:** Add `android:usesCleartextTraffic="true"` to the `<application>` tag:

**Before:**
```xml
    <application
        android:label="frontend"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
```

**After:**
```xml
    <application
        android:label="frontend"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
```

---

## 4. Implementation Procedure

### Step 1: Find computer IP

**Windows:**
```powershell
ipconfig
```
Look for `IPv4 Address` under `Wireless LAN adapter Wi-Fi` (e.g. 192.168.1.100).

**Mac/Linux:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### Step 2: Update backend CORS

- **Docker:** Edit `docker-compose.yml` line 27, add `,http://YOUR_IP` to ALLOWED_ORIGINS.
- **Local backend:** Edit `.env`, add the same value.

Restart backend:
```bash
# Docker
docker-compose down && docker-compose up -d

# Local
# Ctrl+C in backend terminal, then npm run start:dev
```

### Step 3: Edit iOS Info.plist

Edit `frontend/ios/Runner/Info.plist`, insert the NSAppTransportSecurity + permissions block before `</dict>` (see §3.2).

### Step 4: Edit Android AndroidManifest.xml

Edit `frontend/android/app/src/main/AndroidManifest.xml`:

1. Add the 5 permissions after `<manifest>`.
2. Add `android:usesCleartextTraffic="true"` to `<application>`.

### Step 5: iOS Xcode setup (iOS only)

```bash
cd frontend/ios
open Runner.xcworkspace   # ALWAYS .xcworkspace, NOT .xcodeproj
```

In Xcode:

1. Select Runner in the project navigator.
2. **Signing & Capabilities** → **Team:** select your Apple ID.
3. **Bundle Identifier:** change to unique (e.g. `com.yourusername.chatapp`).
4. Connect iPhone via USB, unlock, tap "Trust This Computer" if prompted.

### Step 6: Run Flutter on device

```bash
cd frontend
flutter devices   # Get device ID
flutter run --dart-define=BASE_URL=http://YOUR_IP:3000 -d DEVICE_ID
```

Example:
```bash
flutter run --dart-define=BASE_URL=http://192.168.1.100:3000 -d 00008030-001E34E00162802E
```

---

## 5. Verification Checklist

- [ ] **Auth:** Login/register works on phone.
- [ ] **Socket.IO:** Messages send/receive in real time between phone and web.
- [ ] **Avatar:** Tap avatar in Settings → Camera/Gallery → can select and upload.
- [ ] **Hot reload:** Change theme color, press `r` in terminal → UI updates on phone.
- [ ] **Backend logs:** `docker logs mvp-chat-app-backend-1 --tail 50` shows "Client connected".

---

## 6. Troubleshooting

### 6.1 CORS error

**Symptom:** Login fails, backend logs show "blocked by CORS policy" and `from origin 'X'`.

**Fix:** Add exactly the origin from the error to ALLOWED_ORIGINS in `docker-compose.yml` or `.env`. Example: if error says `from origin 'http://192.168.1.50'`, add `,http://192.168.1.50`. If `from origin 'null'`, add `,null`.

### 6.2 Docker vs .env confusion

**Symptom:** You edited `.env` but CORS still fails.

**Cause:** With Docker, `ALLOWED_ORIGINS` comes from `docker-compose.yml`, not `.env`.

**Fix:** Edit `docker-compose.yml` → `backend.environment.ALLOWED_ORIGINS`. Then `docker-compose down && docker-compose up -d` (restart does not always reload env).

### 6.3 Port 3000 in use

**Windows:**
```powershell
netstat -ano | findstr :3000
taskkill /PID <PID> /F
# Or kill all node:
taskkill /IM node.exe /F
```

**Mac/Linux:**
```bash
lsof -ti:3000 | xargs kill -9
```

### 6.4 Flutter does not see iPhone

- **Windows:** Install iTunes or Apple Devices from Microsoft Store.
- Unlock iPhone, connect USB, tap "Trust This Computer".
- Run `flutter devices` again.

### 6.5 Firewall blocks port 3000 (Windows)

**PowerShell (Admin):**
```powershell
netsh advfirewall firewall add rule name="Flutter Backend Dev" dir=in action=allow protocol=TCP localport=3000
```

### 6.6 iOS: "App Transport Security has blocked cleartext HTTP"

**Symptom:** App crashes or error `-1022`, "blocked a cleartext HTTP".

**Fix:** Ensure §3.2 changes are in Info.plist (NSAppTransportSecurity).

### 6.7 Android: "CLEARTEXT communication not permitted"

**Symptom:** App crashes or logcat shows cleartext not permitted.

**Fix:** Ensure `android:usesCleartextTraffic="true"` is in `<application>` in AndroidManifest.xml.

### 6.8 Xcode: "Signing for Runner requires a development team"

**Fix:** Xcode → Runner → Signing & Capabilities → Team: select Apple ID. Set unique Bundle Identifier.

### 6.9 IP changed (Wi‑Fi reconnect)

1. Run `ipconfig` / `ifconfig` for new IP.
2. Update `docker-compose.yml` ALLOWED_ORIGINS with new IP.
3. `docker-compose down && docker-compose up -d`.
4. `flutter run --dart-define=BASE_URL=http://NEW_IP:3000 -d DEVICE_ID`.

---

## 7. Production Next Steps

This setup is **development only**. Before App Store / Google Play:

| Step | Action |
|------|--------|
| Backend | Deploy to Render.com (or similar) with HTTPS |
| iOS | Remove NSAppTransportSecurity block or use NSExceptionDomains for dev IP only |
| Android | Remove `android:usesCleartextTraffic="true"` |
| Flutter build | `flutter build ipa` / `flutter build appbundle` with `--dart-define=BASE_URL=https://your-api.com` |
| iOS signing | Apple Developer Program ($99/year), provisioning profiles |
| Android signing | Create keystore, configure `android/key.properties`, build signed AAB |

---

## 8. Quick Reference

### Commands

```bash
# Find IP
ipconfig                    # Windows
ifconfig | grep "inet "     # Mac/Linux

# Restart backend (Docker)
docker-compose down && docker-compose up -d

# List devices
flutter devices

# Run on device
cd frontend
flutter run --dart-define=BASE_URL=http://YOUR_IP:3000 -d DEVICE_ID

# Hot reload during run
r   # Hot reload
R   # Hot restart
q   # Quit
```

### File Map

| Change | File |
|--------|------|
| CORS (Docker) | `docker-compose.yml` line 27 |
| CORS (local) | `.env` |
| iOS HTTP + permissions | `frontend/ios/Runner/Info.plist` |
| Android permissions + cleartext | `frontend/android/app/src/main/AndroidManifest.xml` |
| BASE_URL usage | `frontend/lib/config/app_config.dart` (read-only) |

---

## Document Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-04 | Initial source of truth based on mobile-deployment-plan |

---

*This document is the single source of truth for mobile deployment (debug on physical device).*
