# Deployment — Oracle Cloud Free Tier

**Cel:** Uruchomienie Fireplace na darmowym serwerze dla ~15 użytkowników
**Koszt:** $0/mies (opcjonalnie domena ~$10/rok)
**Stack:** Oracle Cloud ARM VM + Docker Compose + Nginx + Let's Encrypt

---

## Etap 0: Przygotowanie (przed rejestracją)

### Czego potrzebujesz
- Karta kredytowa/debetowa (tylko weryfikacja tożsamości, nie pobiera opłat)
- Adres email
- Opcjonalnie: własna domena (Namecheap, Cloudflare Registrar)

### Bez domeny (tymczasowo)
Możesz użyć bezpłatnej subdomeny np. z `nip.io` — `<IP>.nip.io` działa jako domena i obsługuje SSL.

---

## Etap 1: Rejestracja Oracle Cloud

1. Wejdź na **cloud.oracle.com** -> "Start for free"
2. Wybierz **Home Region** — wybierz `Frankfurt` lub `Amsterdam` (EU, GDPR, niskie opóźnienia z Polski)
   - **WAŻNE: Region nie można zmienić po rejestracji**
3. Wypełnij dane, zweryfikuj kartę (charge $1, zwracany)
4. Poczekaj na aktywację konta (kilka minut do godziny)

**Jeśli konto zostanie odrzucone:** Spróbuj ponownie z innym emailem lub skontaktuj się z supportem Oracle — to znany problem.

---

## Etap 2: Tworzenie VM (instancja ARM)

1. Oracle Cloud Console -> **Compute** -> **Instances** -> **Create Instance**

2. Konfiguracja:
   ```
   Name: fireplace-server
   Image: Ubuntu 22.04 (Canonical)
   Shape: Ampere (ARM) -> VM.Standard.A1.Flex
     - OCPU: 4
     - Memory: 24 GB
   ```

3. **Networking:**
   - Utwórz nową VCN (Virtual Cloud Network) lub użyj istniejącej
   - Subnet: public
   - Assign public IPv4: YES

4. **SSH Keys:**
   - "Generate SSH key pair" -> pobierz plik `.key` (prywatny)
   - Zachowaj go bezpiecznie — jedyny sposób dostępu do serwera

5. Kliknij **Create** — VM gotowa za ~2 minuty

---

## Etap 3: Otwieranie portów (Security List)

Oracle domyślnie blokuje wszystko oprócz SSH.

1. **Networking** -> **Virtual Cloud Networks** -> Twoja VCN -> **Security Lists** -> Default
2. **Add Ingress Rules:**

| Source CIDR | Protocol | Port | Opis |
|-------------|----------|------|------|
| 0.0.0.0/0 | TCP | 80 | HTTP (redirect do HTTPS) |
| 0.0.0.0/0 | TCP | 443 | HTTPS |

3. Dodatkowo na samej VM (Ubuntu firewall):
```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

---

## Etap 4: Pierwsze logowanie i setup serwera

```bash
# Połącz się przez SSH (z Windowsa: PowerShell lub Git Bash)
ssh -i ~/ścieżka/do/klucza.key ubuntu@<PUBLIC_IP>
```

### Instalacja Docker + Docker Compose
```bash
# Aktualizacja systemu
sudo apt update && sudo apt upgrade -y

# Docker (oficjalny skrypt)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Dodaj użytkownika do grupy docker (bez sudo)
sudo usermod -aG docker ubuntu
newgrp docker

# Weryfikacja
docker --version
docker compose version
```

### Instalacja Nginx + Certbot
```bash
sudo apt install nginx certbot python3-certbot-nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## Etap 5: Konfiguracja DNS (domena)

### Opcja A: Masz własną domenę
1. W panelu domeny (Cloudflare/Namecheap) dodaj rekord A:
   ```
   Type: A
   Name: @ (lub subdomena np. chat)
   Value: <PUBLIC_IP Oracle VM>
   TTL: Auto
   ```
2. Poczekaj na propagację DNS (5-30 minut)

### Opcja B: Bez domeny (tymczasowe rozwiązanie)
Użyj `<IP>.nip.io` jako pseudo-domeny — np. `1.2.3.4.nip.io`
Działa z Let's Encrypt.

---

## Etap 6: Konfiguracja Nginx + SSL

### Tymczasowa konfiguracja HTTP (do certyfikatu)
```bash
sudo nano /etc/nginx/sites-available/fireplace
```

```nginx
server {
    listen 80;
    server_name twoja-domena.com;  # lub <IP>.nip.io

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/fireplace /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Uzyskanie certyfikatu SSL
```bash
sudo certbot --nginx -d twoja-domena.com
# Podaj email, zaakceptuj warunki
# Certbot automatycznie zaktualizuje config Nginx do HTTPS
```

Certbot automatycznie doda cron dla odnowienia certyfikatu co 90 dni.

---

## Etap 7: Deployment aplikacji

### Transfer plików na serwer
```bash
# Z lokalnego komputera (Windows Git Bash):
scp -i ~/klucz.key -r ./backend ubuntu@<IP>:~/fireplace/
scp -i ~/klucz.key ./docker-compose.yml ubuntu@<IP>:~/fireplace/
```

Lub użyj **git**:
```bash
# Na serwerze:
sudo apt install git -y
git clone https://github.com/TWOJE_REPO/fireplace.git ~/fireplace
cd ~/fireplace
```

### Zmienne środowiskowe produkcyjne
```bash
# Na serwerze:
nano ~/fireplace/.env
```

```env
# Baza danych
DB_HOST=db
DB_PORT=5432
DB_USER=postgres
DB_PASS=SILNE_HASLO_MIN_20_ZNAKÓW
DB_NAME=chatdb

# JWT — OBOWIĄZKOWO nowe, losowe (min 64 znaki)
JWT_SECRET=wygeneruj_tutaj_64_losowe_znaki_abcdef1234567890...

# Cloudinary (te same co w dev)
CLOUDINARY_CLOUD_NAME=twoj_cloud
CLOUDINARY_API_KEY=twoj_klucz
CLOUDINARY_API_SECRET=twoj_secret

# CORS — TYLKO twoja domena
ALLOWED_ORIGINS=https://twoja-domena.com

# FCM (opcjonalnie)
# FIREBASE_SERVICE_ACCOUNT=...
```

**Generowanie JWT_SECRET:**
```bash
openssl rand -hex 64
```

### Uruchomienie
```bash
cd ~/fireplace
docker compose up -d
docker compose logs -f  # sprawdź czy wszystko działa
```

---

## Etap 8: Build frontendu

Flutter web builduje się na **lokalnym komputerze** (Windows), a pliki wgrywamy na serwer.

```bash
# Lokalnie:
cd frontend
flutter build web --dart-define=BASE_URL=https://twoja-domena.com

# Wynik: frontend/build/web/
```

### Serwowanie frontendu przez Nginx

```bash
# Skopiuj build na serwer
scp -i ~/klucz.key -r frontend/build/web ubuntu@<IP>:~/fireplace/frontend-build/
```

Zaktualizuj Nginx config:
```nginx
server {
    listen 443 ssl;
    server_name twoja-domena.com;

    # SSL (wypełnione przez certbot)
    ssl_certificate /etc/letsencrypt/live/twoja-domena.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/twoja-domena.com/privkey.pem;

    # Frontend (Flutter web)
    root /home/ubuntu/fireplace/frontend-build;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;  # SPA routing
    }

    # Backend API + WebSocket
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Socket.IO
    location /socket.io/ {
        proxy_pass http://localhost:3000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}

server {
    listen 80;
    server_name twoja-domena.com;
    return 301 https://$host$request_uri;  # redirect HTTP -> HTTPS
}
```

---

## Etap 9: Backupy bazy danych

```bash
# Utwórz skrypt backupu
nano ~/backup-db.sh
```

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=~/backups
mkdir -p $BACKUP_DIR

docker exec fireplace-db-1 pg_dump -U postgres chatdb > $BACKUP_DIR/chatdb_$DATE.sql

# Zostaw tylko 7 ostatnich backupów
ls -t $BACKUP_DIR/*.sql | tail -n +8 | xargs rm -f

echo "Backup done: chatdb_$DATE.sql"
```

```bash
chmod +x ~/backup-db.sh

# Cron: backup codziennie o 3:00
crontab -e
# Dodaj: 0 3 * * * /home/ubuntu/backup-db.sh
```

---

## Etap 10: Security checklist

- [ ] SSH tylko z kluczem (wyłącz hasła): `PasswordAuthentication no` w `/etc/ssh/sshd_config`
- [ ] Fail2ban (ochrona przed brute-force SSH):
  ```bash
  sudo apt install fail2ban -y
  sudo systemctl enable fail2ban
  ```
- [ ] DB nie wystawiona na zewnątrz (tylko Docker internal network)
- [ ] JWT_SECRET min. 64 znaki, losowe
- [ ] ALLOWED_ORIGINS = tylko twoja domena (nie `*`)
- [ ] Nginx ukrywa wersję serwera: `server_tokens off;` w nginx.conf
- [ ] HTTPS everywhere (HTTP redirectuje do HTTPS)
- [ ] Regularne `sudo apt update && sudo apt upgrade` (cron lub ręcznie co tydzień)

---

## Aktualizacja aplikacji (po zmianach w kodzie)

```bash
# Na serwerze:
cd ~/fireplace
git pull                          # jeśli używasz git
docker compose down
docker compose up -d --build      # rebuild backendu

# Frontend (lokalnie → serwer):
flutter build web --dart-define=BASE_URL=https://twoja-domena.com
scp -i ~/klucz.key -r frontend/build/web/* ubuntu@<IP>:~/fireplace/frontend-build/
```

---

## Monitoring (opcjonalne, darmowe)

- **UptimeRobot** — darmowy monitoring dostępności (ping co 5 min, alert na email)
- `docker stats` — podgląd zużycia RAM/CPU
- `docker compose logs backend` — logi backendu

---

## Podsumowanie kosztów

| Składnik | Koszt |
|----------|-------|
| Oracle Cloud VM (4 OCPU, 24GB RAM) | **$0/mies** |
| Oracle Cloud Storage 200GB | **$0/mies** |
| Let's Encrypt SSL | **$0** |
| Cloudinary (darmowy plan) | **$0** (25GB/mies) |
| Domena (opcjonalnie) | ~$10/rok |
| **Razem** | **$0–$10/rok** |

---

## Kiedy zaczynać?

Ten plan realizujesz gdy aplikacja jest gotowa do produkcji, tzn.:
- Wszystkie główne funkcje działają na web
- Testy przechodzą (`npm test`)
- Mobile (Android) działa poprawnie
- Jesteś gotowy na stałe URL (domena lub IP)
