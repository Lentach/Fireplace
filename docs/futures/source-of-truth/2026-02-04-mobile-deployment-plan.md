# Mobile Deployment Plan - Flutter App na Fizycznym Urządzeniu

**Data utworzenia:** 2026-02-04
**Status:** Draft - do implementacji
**Cel:** Uruchomić aplikację Flutter na fizycznym telefonie (iOS + Android) w trybie debug z backendem działającym na komputerze w lokalnej sieci WiFi.

> **Source of truth (dla agenta):** `docs/futures/2026-02-04-mobile-deployment-plan.md` — pełna dokumentacja w języku angielskim, dokładne ścieżki plików, zmiany w kodzie, troubleshooting. Agent implementujący powinien najpierw przeczytać ten plik.

## Spis Treści
1. [TL;DR - Quick Start](#tldr---quick-start)
2. [Obecna Konfiguracja](#obecna-konfiguracja)
3. [Problem i Rozwiązanie](#problem-i-rozwiązanie)
4. [Implementacja - Kod](#implementacja---kod)
5. [Procedura Uruchomienia](#procedura-uruchomienia)
6. [Weryfikacja](#weryfikacja)
7. [Common Pitfalls](#common-pitfalls---najczęstsze-pułapki)
8. [Troubleshooting](#troubleshooting)
9. [Produkcja - Następne Kroki](#produkcja---następne-kroki)
10. [Quick Reference Card](#quick-reference-card---najważniejsze-komendy)

---

## TL;DR - Quick Start

**Dla niecierpliwych - minimalna ścieżka do uruchomienia app na telefonie:**

1. **Znajdź IP komputera:** `ipconfig` (Windows) → szukaj IPv4 Address (np. `192.168.1.100`)

2. **Backend CORS (Docker):**
   - Edytuj `docker-compose.yml` → linia 27 → `ALLOWED_ORIGINS` → dopisz `,http://TWOJE_IP` (bez portu!)
   - **Ważne:** Origin z mobile app to IP komputera BEZ portu (lub `null`). Port 3000 to BASE_URL, nie origin.
   - `docker-compose down && docker-compose up -d`

3. **iOS - Info.plist:** Dodaj przed `</dict>` (przed końcem pliku):
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
   </dict>
   <key>NSCameraUsageDescription</key>
   <string>Aplikacja potrzebuje dostępu do kamery.</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Aplikacja potrzebuje dostępu do galerii.</string>
   ```

4. **Android - AndroidManifest.xml:**
   - Dodaj po `<manifest>`: 5 permissions (INTERNET, CAMERA, READ_EXTERNAL_STORAGE, READ_MEDIA_IMAGES, WRITE_EXTERNAL_STORAGE)
   - W `<application>` dodaj: `android:usesCleartextTraffic="true"`
   - Zobacz [Implementacja - Kod](#implementacja---kod) dla pełnego kodu

5. **iOS Xcode signing:**
   - `cd frontend/ios && open Runner.xcworkspace`
   - Runner → Signing & Capabilities → Team: wybierz Apple ID
   - Bundle ID: zmień na unikalny (np. `com.yourusername.chatapp`)

6. **Flutter run:**
   ```bash
   flutter devices  # znajdź device_id
   flutter run --dart-define=BASE_URL=http://TWOJE_IP:3000 -d DEVICE_ID
   ```

**Gotowe!** Szczegóły i troubleshooting poniżej.

---

## Obecna Konfiguracja

### Frontend (Flutter)
- **BASE_URL**: `frontend/lib/config/app_config.dart` używa `String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:3000')`
- Przekazywane przez `--dart-define=BASE_URL=...` przy `flutter run`

### Backend (NestJS)
- **CORS**: Źródło zależy od sposobu uruchomienia:
  - **Docker** (`docker-compose up`): wartość z **docker-compose.yml** (sekcja `backend.environment`, linia 27)
  - **Lokalny** (`npm run start` w `backend/`): wartość z pliku **.env** (ConfigModule)
- **Obecna wartość w docker-compose.yml:**
  - `http://localhost:3000` - backend (dev)
  - `http://localhost:8080` - web frontend (dev)
  - `http://192.168.1.11:8080` - nginx web frontend (Docker network)
  - **Dla mobile app:** musisz **DODAĆ** origin z telefonu (najczęściej IP komputera **bez portu**, np. `http://192.168.1.100`, lub `null`)

### iOS (frontend/ios/Runner/Info.plist)
- ❌ **BRAK** `NSAppTransportSecurity` - iOS domyślnie blokuje HTTP connections
- ❌ **BRAK** camera/photo permissions (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`) - potrzebne dla `image_picker`

### Android (frontend/android/app/src/main/AndroidManifest.xml)
- ❌ **BRAK** `<uses-permission android:name="android.permission.INTERNET"/>` - wymagane dla http/socket.io
- ❌ **BRAK** `android:usesCleartextTraffic="true"` - Android 9+ blokuje HTTP
- ❌ **BRAK** camera/photo permissions - potrzebne dla `image_picker`

## Problem
- Telefon nie ma dostępu do `localhost` - to odnosi się do samego telefonu, nie komputera
- iOS/Android blokują HTTP connections (tylko HTTPS)
- Brak permissions dla kamery/galerii (avatar update nie będzie działać)

## Implementacja - Kod

Wszystkie zmiany w plikach konfiguracyjnych. **3 pliki do edycji:**

### 1. Backend CORS

**Uwaga:** Przy uruchomieniu backendu przez **Docker** (`docker-compose up`) wartość `ALLOWED_ORIGINS` pochodzi z **docker-compose.yml** (sekcja `backend.environment`), nie z `.env`. Przy uruchomieniu lokalnym (`npm run start` w `backend/`) — z pliku **.env**.

**Jeśli używasz Docker:** edytuj `docker-compose.yml`, w sekcji `backend.environment` dopisz swoje IP do `ALLOWED_ORIGINS` (np. `http://192.168.1.100` **bez portu** - origin z mobile app nie zawiera portu backendu). Potem: `docker-compose down` i `docker-compose up -d`.

**Jeśli backend lokalnie:** edytuj `.env` w katalogu głównym repo.

**Lokalizacja:** `.env` i `docker-compose.yml` w katalogu głównym projektu (`C:\Users\Lentach\Desktop\mvp-chat-app\`).

**Uwaga o ścieżkach:** Wszystkie absolutne ścieżki w tym dokumencie używają `Desktop` (wielka D), nie `desktop`.

**Zmiana (treść ALLOWED_ORIGINS):** Dodaj IP komputera (lub origin z błędu CORS, jeśli inny)

**PRZED:**
```env
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
```

**PO (przykład z IP 192.168.1.100):**
```env
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://192.168.1.100
```

**❗ Ważne:**
- Zastąp `192.168.1.100` swoim IP z `ipconfig` (Windows) lub `ifconfig` (Mac/Linux)
- **NIE dodawaj portu :3000** do origin! Origin z mobile app to IP komputera BEZ portu (lub `null`)
- Port 3000 to adres backendu (BASE_URL), nie origin klienta

**💡 Nota techniczna - CORS w aplikacjach mobilnych:**
- Aplikacje mobilne Flutter (http/dio) **zazwyczaj NIE wysyłają** `Origin` header przy zwykłych REST requestach (w przeciwieństwie do przeglądarek)
- CORS może **nie być sprawdzany** dla `/auth/login`, `/auth/register` itp., jeśli brak Origin header
- **Socket.IO może wysyłać Origin** - zależy od implementacji `socket_io_client` dla Dart
- **Jeśli pojawi się błąd CORS** podczas testów: sprawdź backend logs (`docker logs mvp-chat-app-backend-1`), znajdź `from origin '...'` w błędzie i dodaj **dokładnie ten origin** do `ALLOWED_ORIGINS`
- Origin może być: `null`, `http://IP_TELEFONU`, lub w ogóle nie występować

### 2. iOS - `frontend/ios/Runner/Info.plist`

**Lokalizacja:** `C:\Users\Lentach\Desktop\mvp-chat-app\frontend\ios\Runner\Info.plist`

**Zmiana:** Dodaj NSAppTransportSecurity + camera/photo permissions

**Dodaj przed zamykającym `</dict>` (przed końcem pliku):**

```xml
	<!-- Allow HTTP connections to local IP (development only) -->
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<!-- Camera permission for avatar upload -->
	<key>NSCameraUsageDescription</key>
	<string>Aplikacja potrzebuje dostępu do kamery, aby zaktualizować zdjęcie profilowe.</string>
	<!-- Photo library permission for avatar upload -->
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Aplikacja potrzebuje dostępu do galerii, aby wybrać zdjęcie profilowe.</string>
```

### 3. Android - `frontend/android/app/src/main/AndroidManifest.xml`

**Lokalizacja:** `C:\Users\Lentach\Desktop\mvp-chat-app\frontend\android\app\src\main\AndroidManifest.xml`

**Zmiana A:** Dodaj permissions po `<manifest>` (przed `<application>`):

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

(`READ_MEDIA_IMAGES` — zalecane od Android 13 / API 33 do wyboru zdjęć.)

**Zmiana B:** Dodaj `android:usesCleartextTraffic="true"` w `<application>`:

```xml
    <application
        android:label="frontend"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
```

---

## Procedura Uruchomienia

**📌 Uwaga o setupie backendu:**
Ten guide zakłada backend w **Docker** (`docker-compose up`). Jeśli używasz **lokalnego backendu** (`npm run start:dev` w `backend/`):
- Wszędzie gdzie mówi "edytuj `docker-compose.yml`" → edytuj `.env` zamiast tego
- Restart backendu: `Ctrl+C` i `npm run start:dev` zamiast `docker-compose down && up`
- Wszystkie inne kroki (iOS, Android, flutter run) są identyczne

---

### Krok 1: Znajdź IP Komputera
Telefon musi łączyć się z IP komputera w lokalnej sieci.

**Windows:**
```bash
ipconfig
```
Szukaj `IPv4 Address` w sekcji `Wireless LAN adapter Wi-Fi` (np. `192.168.1.100`)

**Mac/Linux:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Przykładowy IP: `192.168.1.100`

### Krok 2: Backend - Dodaj IP do CORS

**Docker:** Edytuj `docker-compose.yml` → sekcja `backend.environment` → `ALLOWED_ORIGINS` (dopisz np. `,http://192.168.1.100` **bez portu**).
**Lokalny backend:** Edytuj `.env` → ta sama wartość (IP bez portu).

**💡 Ważne - CORS Origin ≠ BASE_URL:**
- **BASE_URL** (używany w `flutter run`): `http://192.168.1.100:3000` - pełny adres backendu z portem
- **Origin** (w ALLOWED_ORIGINS): `http://192.168.1.100` - adres klienta BEZ portu, lub `null`
- Mobile apps często nie wysyłają Origin header lub wysyłają IP telefonu/komputera bez portu

Zastąp `192.168.1.100` swoim IP z Kroku 1. W razie błędu CORS w logach dodaj **origin z komunikatu** (często IP telefonu).

**Restart backend (Docker):**
```bash
docker-compose down && docker-compose up -d
```
**Uwaga:** `docker-compose restart backend` jest szybsze, ale może nie załadować zmian w `environment` z docker-compose.yml. Dla pewności użyj `down && up`.

### Krok 3: iOS - HTTP Exception + Permissions

**Plik:** `frontend/ios/Runner/Info.plist`

**PRZED (ostatnie linie pliku):**
```xml
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
</dict>
</plist>
```

**PO (dodaj przed zamykającym `</dict>`):**
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
	<string>Aplikacja potrzebuje dostępu do kamery, aby zaktualizować zdjęcie profilowe.</string>
	<!-- Photo library permission for avatar upload -->
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Aplikacja potrzebuje dostępu do galerii, aby wybrać zdjęcie profilowe.</string>
</dict>
</plist>
```

**Uwaga:** `NSAllowsArbitraryLoads = true` wyłącza ATS (App Transport Security) dla WSZYSTKICH connections. W produkcji użyj `NSExceptionDomains` dla konkretnego IP lub HTTPS.

### Krok 4: Android - Permissions + HTTP

**Plik:** `frontend/android/app/src/main/AndroidManifest.xml`

**PRZED (cały plik):**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="frontend"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            ...
        </activity>
        ...
    </application>
    <queries>
        ...
    </queries>
</manifest>
```

**PO (pełny nowy plik):**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Network access for API + Socket.IO -->
    <uses-permission android:name="android.permission.INTERNET"/>

    <!-- Camera/Photo permissions for avatar upload -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28"/>

    <application
        android:label="frontend"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

**Kluczowe zmiany:**
1. Dodane 5 permissions na początku (INTERNET, CAMERA, READ_EXTERNAL_STORAGE, READ_MEDIA_IMAGES, WRITE_EXTERNAL_STORAGE)
2. Dodane `android:usesCleartextTraffic="true"` w `<application>` - pozwala na HTTP connections (Android 9+)

### Krok 5: iOS Setup - Xcode + Device

**A) Otwórz projekt w Xcode:**
```bash
cd frontend/ios
open Runner.xcworkspace  # ZAWSZE .xcworkspace, NIE .xcodeproj!
```

**⚠️ Ważne:** Otwieraj `Runner.xcworkspace`, NIE `Runner.xcodeproj`. Workspace jest wymagany przez CocoaPods (Flutter używa CocoaPods dla native dependencies).

**B) Podłącz iPhone przez USB** i odblokuj telefon.

**C) W Xcode:**
1. Wybierz swoje urządzenie w górnym menu (obok "Runner")
2. **Signing & Capabilities** → Team: wybierz swój Apple ID (bezpłatny Personal Team)
3. Bundle Identifier: zmień na unikalny (np. `com.twojanazwa.frontend`)

**D) Trust Developer na iPhonie:**
Po pierwszym uruchomieniu: Ustawienia → Ogólne → VPN i zarządzanie urządzeniami → zaufaj developerowi

### Krok 6: Flutter Run z BASE_URL

**Terminal (Windows PowerShell):**
```bash
cd frontend

# Zamień 192.168.1.100 na swój IP z Kroku 1
flutter run --dart-define=BASE_URL=http://192.168.1.100:3000 -d <device_id>
```

**Znalezienie device_id:**
```bash
flutter devices
```

Szukaj:
- iOS: `iPhone 15 (mobile) • 00008030-001E34E00162802E • ios • iOS 17.2.1`
- Android: `SM G973F (mobile) • R58M41JBKNV • android-arm64 • Android 13`

Device ID to drugi element (iOS: długi hex string, Android: serial number urządzenia).

**Przykład:**
```bash
flutter run --dart-define=BASE_URL=http://192.168.1.100:3000 -d 00008030-001E34E00162802E
```

### Krok 7: Test na Telefonie

Po uruchomieniu (`flutter run` z Kroku 6) aplikacja powinna się otworzyć na telefonie.

**Oczekiwany output w terminalu:**
```
Launching lib/main.dart on iPhone 15 in debug mode...
Running Xcode build...
 └─Compiling, linking and signing...                        3.2s
Xcode build done.                                           15.4s
Syncing files to device iPhone 15...                               89ms

Flutter run key commands.
r Hot reload.
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application running).
c Clear the screen
q Quit (terminate the application on the device).

💪 Running with sound null safety 💪

An Observatory debugger and profiler on iPhone 15 is available at: http://127.0.0.1:51234/
The Flutter DevTools debugger and profiler on iPhone 15 is available at: http://127.0.0.1:9100/
```

---

## Weryfikacja

### Test 1: Auth + Backend Connection

1. **Otwórz app na telefonie** - powinieneś zobaczyć ekran logowania
2. **Zaloguj się** istniejącym użytkownikiem lub zarejestruj nowego
3. **Sprawdź backend logs:**
   ```bash
   docker logs mvp-chat-app-backend-1 --tail 50
   ```
   Szukaj:
   ```
   [ChatGateway] Client connected: <socket_id>
   [ChatGateway] User authenticated: { id: 1, email: 'user@example.com', username: 'user' }
   ```

**✅ Sukces:** Jesteś zalogowany i widzisz listę konwersacji (lub ekran "No conversations")

**❌ Błąd:** Sprawdź [Troubleshooting](#troubleshooting)

### Test 2: Socket.IO (Wiadomości)

1. **Zaloguj się na dwóch urządzeniach:**
   - Telefon: zalogowany jako User A
   - Komputer: otwórz `http://localhost:8080` (web app), zaloguj jako User B
2. **Wyślij wiadomość** z telefonu (User A) do User B
3. **Sprawdź czy dotarła** na komputerze (User B powinien zobaczyć wiadomość)
4. **Wyślij odpowiedź** z komputera (User B) do User A
5. **Sprawdź na telefonie** (User A powinien zobaczyć odpowiedź)

**✅ Sukces:** Wiadomości wysyłają się i odbierają w czasie rzeczywistym

**❌ Błąd:** Sprawdź backend logs, czy Socket.IO connection jest aktywny

### Test 3: Avatar Upload (Camera/Galeria)

1. **Przejdź do Settings** (ikona Settings w bottom nav)
2. **Tap na avatar** (zielony okrąg z inicjałami lub zdjęcie)
3. **Wybierz "Camera" lub "Gallery"**
4. **iOS:** Powinno pojawić się "App wants to access camera/photos" - kliknij "Allow"
5. **Android:** Podobny dialog permissions

**✅ Sukces:** Możesz wybrać zdjęcie i zaktualizować avatar

**❌ Błąd:** Jeśli crash lub "Permission denied", sprawdź czy dodałeś permissions w Info.plist/AndroidManifest

### Test 4: Hot Reload (Development)

1. **Zmień kolor** w `frontend/lib/theme/rpg_theme.dart` (np. `primaryDark`)
2. **W terminalu naciśnij `r`** (hot reload)
3. **Sprawdź telefon** - kolor powinien się zmienić bez restartu app

**✅ Sukces:** Hot reload działa, możesz szybko iterować nad UI

---

## Common Pitfalls - Najczęstsze Pułapki

### 1. Backend w Docker vs lokalny - gdzie edytować ALLOWED_ORIGINS

**Problem:** Edytujesz `.env`, restartujesz backend, ale CORS nadal blokuje requesty.

**Przyczyna:** W Docker `ALLOWED_ORIGINS` jest hardcoded w `docker-compose.yml` (linia 27), nie czytany z `.env`.

**Rozwiązanie:**
- **Docker setup:** Edytuj `docker-compose.yml` → sekcja `backend.environment` → `ALLOWED_ORIGINS`
- **Lokalny setup:** Edytuj `.env` w głównym katalogu

**Weryfikacja:** Po zmianie sprawdź backend logs:
```bash
docker logs mvp-chat-app-backend-1 | grep ALLOWED_ORIGINS
```

### 2. Wiele uruchomionych backendów (port conflict)

**Problem:** `docker-compose up` fails z błędem "port 3000 already in use".

**Przyczyna:** Masz uruchomiony lokalny backend (`npm run start:dev`) lub inny proces na porcie 3000.

**Rozwiązanie (Windows):**
```powershell
# Znajdź proces na porcie 3000
netstat -ano | findstr :3000

# Zabij proces (zamień <PID> na numer z poprzedniej komendy)
taskkill /PID <PID> /F

# Lub zabij wszystkie node.exe
taskkill /IM node.exe /F
```

**Rozwiązanie (Mac/Linux):**
```bash
# Znajdź i zabij proces
lsof -ti:3000 | xargs kill -9
```

### 3. iPhone/iPad - "Trust This Computer" nie pojawia się

**Problem:** Podłączasz iPhone, ale `flutter devices` nie widzi urządzenia.

**Przyczyna:** Dialog "Trust" pojawia się tylko gdy telefon jest **odblokowany** i ekran jest aktywny.

**Rozwiązanie:**
1. Odłącz iPhone
2. **Odblokuj telefon** (wprowadź PIN/Face ID)
3. Podłącz iPhone ponownie
4. Dialog "Trust This Computer" powinien się pojawić na iPhonie
5. Kliknij "Trust"
6. `flutter devices` powinno teraz wykryć urządzenie

### 4. Firewall blokuje port 3000 (Windows)

**Problem:** Backend działa (`docker ps` pokazuje running), ale telefon nie może połączyć się z `http://IP:3000`.

**Przyczyna:** Windows Defender Firewall blokuje incoming connections na porcie 3000.

**Rozwiązanie (Windows PowerShell jako Administrator):**
```powershell
# Dodaj regułę firewall dla portu 3000
netsh advfirewall firewall add rule name="Flutter Backend Dev" dir=in action=allow protocol=TCP localport=3000

# Weryfikacja - sprawdź czy reguła została dodana
netsh advfirewall firewall show rule name="Flutter Backend Dev"
```

### 5. BASE_URL ze starym IP - po zmianie sieci WiFi

**Problem:** Wczoraj aplikacja działała, dziś "Network error" / "Connection refused".

**Przyczyna:** IP komputera zmieniło się (po reconnect do WiFi, router DHCP nadał nowy adres).

**Rozwiązanie:**
1. Sprawdź nowy IP komputera: `ipconfig` (Windows) / `ifconfig` (Mac/Linux)
2. Zaktualizuj `docker-compose.yml` → `ALLOWED_ORIGINS` → zmień stary IP komputera na nowy (BEZ portu, np. `http://192.168.1.100`)
3. Uruchom `flutter run` z nowym BASE_URL:
   ```bash
   flutter run --dart-define=BASE_URL=http://NOWY_IP:3000 -d <device_id>
   ```
4. Restart backend: `docker-compose down && docker-compose up -d`

**💡 Przypomnienie:** Origin w ALLOWED_ORIGINS to IP komputera **bez portu**. BASE_URL w flutter run to pełny adres backendu **z portem :3000**.

### 6. Xcode - "Runner is not signed"

**Problem:** iOS build fails z błędem signing.

**Przyczyna:** Nie ustawiono Team w Xcode.

**Rozwiązanie:**
1. Otwórz `frontend/ios/Runner.xcworkspace` w Xcode (NIE .xcodeproj!)
2. Wybierz **Runner** (blue icon) w Project Navigator (lewy panel)
3. Tab **Signing & Capabilities**
4. **Team:** wybierz swój Apple ID
   - Jeśli nie ma Apple ID: Xcode → Settings → Accounts → Add (+) → Apple ID
5. **Bundle Identifier:** zmień na unikalny (np. `com.yourusername.chatapp`)
6. Zamknij Xcode i uruchom ponownie `flutter run`

---

## Troubleshooting

### Problem 1: "flutter devices" nie widzi iPhone

**Objawy:**
```bash
flutter devices
# No devices detected
```

**Rozwiązanie (Windows):**
1. Zainstaluj **iTunes** lub **Apple Devices** (z Microsoft Store)
2. Podłącz iPhone przez USB
3. **Odblokuj iPhone** i kliknij "Trust This Computer"
4. Uruchom ponownie `flutter devices`

**Rozwiązanie (Mac):**
```bash
# Sprawdź czy iPhone jest widoczny
xcrun xctrace list devices

# Jeśli nie, restart usbmuxd
sudo killall -STOP -c usbd
```

### Problem 2: "Network error" / "Connection refused"

**Objawy:** App się otwiera, ale login fails z "Network error" lub "Connection refused"

**Przyczyny:**
- Telefon i komputer w **różnych sieciach WiFi**
- Firewall blokuje port 3000
- Zły IP w BASE_URL

**Rozwiązanie:**
1. **Sprawdź sieć:**
   - Telefon: Settings → WiFi → sprawdź nazwę sieci
   - Komputer: Sprawdź czy jesteś w tej samej sieci
2. **Sprawdź firewall (Windows):**
   ```powershell
   # Dodaj regułę dla port 3000
   netsh advfirewall firewall add rule name="Flutter Backend" dir=in action=allow protocol=TCP localport=3000
   ```
3. **Sprawdź IP:**
   ```bash
   # Powinno być 192.168.x.x (local network)
   ipconfig
   ```
4. **Sprawdź backend:**
   ```bash
   docker ps  # Backend powinien być RUNNING
   curl http://192.168.1.100:3000  # Zamień IP
   ```

### Problem 3: iOS - "App Transport Security has blocked a cleartext HTTP"

**Objawy:** App crash lub error w Xcode console:
```
NSURLConnection error: -1022
App Transport Security has blocked a cleartext HTTP (http://) resource load...
```

**Przyczyna:** Nie dodałeś `NSAppTransportSecurity` do Info.plist

**Rozwiązanie:** Dodaj do `frontend/ios/Runner/Info.plist` (zobacz [Implementacja - Kod](#implementacja---kod))

### Problem 4: Android - "CLEARTEXT communication not permitted"

**Objawy:** App crash lub logcat error:
```
CLEARTEXT communication to 192.168.1.100 not permitted by network security policy
```

**Przyczyna:** Nie dodałeś `android:usesCleartextTraffic="true"`

**Rozwiązanie:** Dodaj w `<application>` tag w AndroidManifest.xml (zobacz [Implementacja - Kod](#implementacja---kod))

### Problem 5: Xcode - "Signing for Runner requires a development team"

**Objawy:** Xcode build fails:
```
error: Signing for "Runner" requires a development team. Select a development team in the Signing & Capabilities editor.
```

**Rozwiązanie:**
1. Otwórz `frontend/ios/Runner.xcworkspace` w Xcode
2. Kliknij **Runner** (blue icon) w lewym panelu
3. **Signing & Capabilities** tab
4. **Team:** wybierz swój Apple ID (dodaj w Xcode → Preferences → Accounts jeśli nie ma)
5. **Bundle Identifier:** zmień na unikalny (np. `com.twojanazwa.frontend`)

### Problem 6: "Camera permission denied" / Crash on avatar tap

**Objawy:** App crashuje gdy tap na avatar lub pokazuje "Permission denied"

**Przyczyna:** Nie dodałeś camera/photo permissions

**Rozwiązanie:**
- **iOS:** Dodaj `NSCameraUsageDescription` i `NSPhotoLibraryUsageDescription` do Info.plist
- **Android:** Dodaj `CAMERA` i `READ_EXTERNAL_STORAGE` permissions do AndroidManifest.xml
- Zobacz [Implementacja - Kod](#implementacja---kod)

### Problem 7: CORS error w backend logs

**Objawy:** Backend logs pokazują:
```
Access to XMLHttpRequest at 'http://192.168.1.100:3000/auth/login' from origin 'http://192.168.1.50' has been blocked by CORS policy
```
lub
```
Access blocked from origin 'null'
```

**Przyczyna:** Origin z requestu nie jest w `ALLOWED_ORIGINS`

**Rozwiązanie:**
1. **Sprawdź dokładny origin w backend logs** - znajdź linię z `from origin '...'` w błędzie CORS
2. **Docker:** Edytuj `docker-compose.yml` → sekcja `backend.environment` → `ALLOWED_ORIGINS` → dopisz origin z błędu (np. `,http://192.168.1.50` lub `,null`)
3. **Lokalny backend:** Edytuj `.env` → ta sama wartość
4. Restart backend:
   ```bash
   # Docker
   docker-compose down && docker-compose up -d

   # Lokalny
   # Ctrl+C i npm run start:dev
   ```

**💡 Uwaga:**
- Origin w błędzie CORS to adres **klienta** (telefon), nie serwera
- Dla Flutter apps origin może być `null`, `http://IP_TELEFONU` (bez portu), lub w ogóle nie występować
- Jeśli origin to `null`, dodaj dokładnie: `ALLOWED_ORIGINS=...,null` (jako string)

### Problem 8: Backend nie startuje po zmianie .env / docker-compose.yml

**Rozwiązanie:**
```bash
# Docker - po zmianie docker-compose.yml
docker-compose down
docker-compose up -d

# Sprawdź logs
docker logs mvp-chat-app-backend-1 --tail 50
```

**💡 Uwaga:**
- **Docker:** Zmiana w `.env` **nie zadziała** jeśli zmienna jest hardcoded w `docker-compose.yml` (sekcja `backend.environment`). Musisz edytować `docker-compose.yml`.
- **Lokalny backend:** Zmiana w `.env` wymaga restartu procesu (`Ctrl+C` i `npm run start:dev`)
- `docker-compose restart backend` może **nie załadować** zmian w `environment` z docker-compose.yml - bezpieczniej: `down && up`

---

## Pliki do Modyfikacji (Podsumowanie)

| Plik | Zmiana | Czas |
|------|--------|------|
| `docker-compose.yml` (Docker) lub `.env` (lokalny) | Dodaj IP/origin do `ALLOWED_ORIGINS` | 1 min |
| `frontend/ios/Runner/Info.plist` | NSAppTransportSecurity + camera/photo permissions | 2 min |
| `frontend/android/app/src/main/AndroidManifest.xml` | INTERNET + usesCleartextTraffic + camera/photo permissions | 2 min |

## Produkcja - Następne Kroki

Ten setup jest **TYLKO dla development**. Przed publikacją w App Store/Google Play:

### 1. Backend Deployment (Render.com)

**Co zrobić:**
- Deploy backend na Render.com z managed PostgreSQL
- Render auto-SSL (HTTPS)
- Update `ALLOWED_ORIGINS` w Render.com environment variables:
  ```
  ALLOWED_ORIGINS=https://twoja-domena.com
  ```

**Backend URL:** `https://twoja-app.onrender.com`

### 2. iOS - Usuń HTTP Exception

**Plik:** `frontend/ios/Runner/Info.plist`

**USUŃ (lub zamień na NSExceptionDomains dla dev):**
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>  <!-- ❌ Nie akceptowane w App Store review! -->
</dict>
```

**Produkcja:** Użyj HTTPS URL, ATS będzie działać automatycznie.

**Development (alternatywa):** Jeśli chcesz mieć HTTP tylko dla local IP:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>192.168.1.100</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

### 3. Android - Usuń usesCleartextTraffic

**Plik:** `frontend/android/app/src/main/AndroidManifest.xml`

**USUŃ:**
```xml
android:usesCleartextTraffic="true"  <!-- ❌ Nie zalecane w produkcji! -->
```

**Produkcja:** Użyj HTTPS URL, cleartext nie będzie potrzebny.

### 4. Flutter Build - Production BASE_URL

**Debug (development):**
```bash
flutter run --dart-define=BASE_URL=http://192.168.1.100:3000
```

**Release (production):**
```bash
# iOS
flutter build ipa --dart-define=BASE_URL=https://twoja-app.onrender.com

# Android
flutter build apk --dart-define=BASE_URL=https://twoja-app.onrender.com
# lub AAB (Google Play)
flutter build appbundle --dart-define=BASE_URL=https://twoja-app.onrender.com
```

### 5. iOS Signing (App Store)

**Development (Personal Team):** Bezpłatny Apple ID, max 7 dni validity, tylko personal devices

**Production (Apple Developer Program):** $99/rok, pełne provisioning profiles, App Store distribution

**Kroki:**
1. Enroll in Apple Developer Program: https://developer.apple.com/programs/
2. Xcode → Signing & Capabilities → Team: wybierz płatny team
3. Xcode → Product → Archive → Distribute App → App Store Connect
4. App Store Connect: dodaj screenshots, opis, submit for review

### 6. Android Signing (Google Play)

**Generowanie keystore:**
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Konfiguracja:** `frontend/android/key.properties`
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=C:/Users/YourName/upload-keystore.jks
```

**Build signed AAB:**
```bash
flutter build appbundle --dart-define=BASE_URL=https://twoja-app.onrender.com
```

**Upload:** Google Play Console → Create app → Upload AAB

### 7. Checklist przed publikacją

- [ ] Backend na HTTPS (Render.com lub inny)
- [ ] Usuń `NSAllowsArbitraryLoads` z Info.plist
- [ ] Usuń `usesCleartextTraffic` z AndroidManifest.xml
- [ ] Update BASE_URL na production URL
- [ ] Test E2E na production backend
- [ ] iOS signing (Apple Developer)
- [ ] Android signing (keystore)
- [ ] App Store screenshots + opis
- [ ] Google Play screenshots + opis
- [ ] Privacy Policy (wymagane dla obu stores)
- [ ] Test avatar upload (Cloudinary production)
- [ ] Test Socket.IO (production backend: send/receive messages, reconnect after network loss, typing indicators)
- [ ] Beta testing (TestFlight/Internal Testing)

### Android Alternative (jeśli nie masz Androida)
Wszystkie zmiany Android są już w planie - gdy będziesz testować na Android (emulator lub fizyczne urządzenie), po prostu użyj tego samego `flutter run` command z Android device ID.

### Hot Reload
Debug build obsługuje hot reload - po zmianach w kodzie Dart naciśnij `r` w terminalu (hot reload) lub `R` (hot restart).

## Timeline
- Znalezienie IP + zmiana CORS (docker-compose.yml lub .env): **2 min**
- iOS/Android config changes: **5 min**
- iOS Xcode setup (signing): **10-15 min** (jeśli masz Apple ID w Xcode), **20-30 min** (jeśli trzeba dodać Apple ID + trust developer)
- Flutter run + test: **5 min**
- **Total: ~25-35 min** (pierwszy raz z Apple ID), **35-45 min** (bez Apple ID)

## Ryzyko
- **CORS**: Najbardziej prawdopodobny problem. Origin z telefonu może być `null` lub IP komputera BEZ portu. Sprawdź backend logs (`docker logs mvp-chat-app-backend-1`) i dodaj dokładny origin z błędu do `ALLOWED_ORIGINS` w `docker-compose.yml`
- **Xcode signing**: Jeśli nie masz Apple ID dodanego w Xcode, trzeba go dodać (Preferences → Accounts)
- **USB trust**: Pierwszy raz wymaga "Trust This Computer" na iPhonie
- **Firewall**: Windows Defender może blokować port 3000 - dodaj regułę jeśli problem
- **Flutter devices**: Jeśli `flutter devices` nie widzi iPhone, sprawdź czy iTunes/Apple Devices jest zainstalowane (Windows)

---

## Quick Reference Card - Najważniejsze Komendy

### Przygotowanie (raz, przed pierwszym uruchomieniem)

```bash
# 1. Znajdź IP komputera
ipconfig                           # Windows
ifconfig | grep "inet "            # Mac/Linux

# 2. Edytuj ALLOWED_ORIGINS
# Docker: docker-compose.yml → backend.environment → ALLOWED_ORIGINS
# Lokalny: .env → ALLOWED_ORIGINS
# Dodaj: ,http://TWOJE_IP (BEZ portu - origin nie zawiera :3000!)

# 3. Restart backend
docker-compose down && docker-compose up -d

# 4. Edytuj pliki iOS/Android (patrz: Implementacja - Kod)
# - frontend/ios/Runner/Info.plist (NSAppTransportSecurity + permissions)
# - frontend/android/app/src/main/AndroidManifest.xml (INTERNET + permissions + usesCleartextTraffic)

# 5. iOS - Xcode signing
cd frontend/ios
open Runner.xcworkspace
# W Xcode: Runner → Signing & Capabilities → Team: wybierz Apple ID
```

### Codzienne uruchamianie

```bash
# 1. Sprawdź backend
docker ps                          # Backend powinien być running

# 2. Podłącz telefon
# iOS: USB + odblokuj + "Trust This Computer"
# Android: USB + włącz "USB Debugging" w Developer Options

# 3. Sprawdź devices
flutter devices

# 4. Uruchom app
cd frontend
flutter run --dart-define=BASE_URL=http://TWOJE_IP:3000 -d DEVICE_ID

# Przykład:
# flutter run --dart-define=BASE_URL=http://192.168.1.100:3000 -d 00008030-001E34E00162802E
```

### Hot reload podczas development

```
r       # Hot reload (szybki, zachowuje state)
R       # Hot restart (pełny restart, czyści state)
q       # Quit (zamyka app i kończy flutter run)
```

### Troubleshooting - szybkie fixe

```bash
# Backend nie odpowiada
docker-compose down && docker-compose up -d  # zalecane - ładuje zmiany environment
# docker-compose restart backend             # szybsze, ale może nie załadować zmian
docker logs mvp-chat-app-backend-1 --tail 50

# Port 3000 zajęty (Windows)
netstat -ano | findstr :3000
taskkill /PID <PID> /F
taskkill /IM node.exe /F           # zabij wszystkie node.exe

# Port 3000 zajęty (Mac/Linux)
lsof -ti:3000 | xargs kill -9

# Flutter nie widzi iPhone (Windows)
# Zainstaluj iTunes lub Apple Devices z Microsoft Store
# Odłącz + odblokuj + podłącz ponownie

# CORS error
docker logs mvp-chat-app-backend-1 | grep "origin"
# Znajdź origin w błędzie, dodaj do docker-compose.yml → ALLOWED_ORIGINS
docker-compose down && docker-compose up -d

# Firewall blokuje (Windows PowerShell jako Admin)
netsh advfirewall firewall add rule name="Flutter Backend Dev" dir=in action=allow protocol=TCP localport=3000
```

### Weryfikacja setup

```bash
# 1. Backend działa
curl http://TWOJE_IP:3000
# Oczekiwane: {"message":"Welcome to Chat API"} lub podobne

# 2. Backend logs
docker logs mvp-chat-app-backend-1 --tail 50 -f
# Szukaj: "Application is running on: http://[::]:3000"

# 3. Flutter devices
flutter devices
# Powinno pokazać podłączone urządzenie (iOS/Android)

# 4. Backend CORS config
docker logs mvp-chat-app-backend-1 | grep ALLOWED
# Sprawdź czy Twoje IP jest w liście
```

### iOS - dodatkowe

```bash
# Xcode command line tools
xcode-select --install

# Lista urządzeń
xcrun xctrace list devices

# Sprawdź signing
cd frontend/ios
open Runner.xcworkspace
# Runner → Signing & Capabilities → sprawdź Team i Bundle ID
```

### Android - dodatkowe

```bash
# ADB devices (jeśli flutter devices nie działa)
adb devices

# Restart ADB server
adb kill-server
adb start-server

# Sprawdź USB debugging
adb devices -l
# Jeśli "unauthorized": odłącz, w telefonie: Settings → Developer options → Revoke USB debugging authorizations → podłącz ponownie → Allow
```

### Zmiana IP (po zmianie sieci WiFi)

```bash
# 1. Nowy IP komputera
ipconfig  # lub ifconfig

# 2. Update docker-compose.yml
# backend.environment.ALLOWED_ORIGINS → dodaj nowy IP

# 3. Restart backend
docker-compose down && docker-compose up -d

# 4. Flutter run z nowym IP
flutter run --dart-define=BASE_URL=http://NOWY_IP:3000 -d DEVICE_ID
```

---

## Kontakt i Wsparcie

**Problem z planem?** Sprawdź:
1. [Common Pitfalls](#common-pitfalls---najczęstsze-pułapki) - najczęstsze błędy
2. [Troubleshooting](#troubleshooting) - szczegółowe rozwiązania
3. Backend logs: `docker logs mvp-chat-app-backend-1 --tail 50`
4. Flutter console output podczas `flutter run`

**CORS errors?** Zawsze sprawdź `from origin '...'` w backend logs i dodaj dokładnie ten origin do ALLOWED_ORIGINS w docker-compose.yml.
