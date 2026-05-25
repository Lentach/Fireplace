# Deployment — Google Cloud Free Tier

**Cel:** Uruchomienie Fireplace na darmowym serwerze dla ~15 użytkowników
**Koszt:** $0/mies (opcjonalnie domena ~$10/rok)
**Stack:** GCP e2-micro VM + Docker Compose + Nginx + Let's Encrypt

---

## Etap 0: Rejestracja Google Cloud

1. Wejdź na **cloud.google.com** → "Get started for free"
2. Zaloguj się kontem Google
3. Wypełnij dane + zweryfikuj kartę (charge $1, zwracany)
4. Dostaniesz **$300 kredytu na 90 dni** + **Always Free** zasoby po ich wyczerpaniu

> **Always Free e2-micro:** działa wiecznie, nie zużywa kredytu — to właśnie nas interesuje.

---

## Etap 1: Tworzenie VM

1. **Console** → **Compute Engine** → **VM Instances** → **Create Instance**

2. Konfiguracja:
   ```
   Name: fireplace-server
   Region: us-central1  ← WAŻNE: tylko us-east1, us-west1, us-central1 są Always Free
   Zone:   us-central1-a (dowolna)

   Machine type: e2-micro (2 vCPU shared, 1 GB RAM)
   ```

3. **Boot disk:**
   ```
   OS: Ubuntu 22.04 LTS
   Size: 30 GB (maksimum darmowe)
   Type: Standard persistent disk
   ```

4. **Firewall:**
   - ✅ Allow HTTP traffic
   - ✅ Allow HTTPS traffic

5. **SSH Keys** (opcjonalnie — możesz też użyć wbudowanego SSH w przeglądarce):
   - Jeśli chcesz logować się z terminala: Metadata → SSH Keys → Add

6. Kliknij **Create** — VM gotowa za ~1 minutę.

---

## Etap 2: Połączenie z VM

### Opcja A: SSH w przeglądarce (najłatwiej)
Compute Engine → VM Instances → kliknij **SSH** przy swoim serwerze → otworzy się terminal w przeglądarce.

### Opcja B: SSH z terminala (Windows)
```bash
# Pobierz IP z konsoli GCP (External IP)
ssh -i ~/.ssh/google_compute_engine TWOJ_USER@<EXTERNAL_IP>
```

---

## Etap 3: Setup serwera

```bash
# Aktualizacja systemu
sudo apt update && sudo apt upgrade -y

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Nginx + Certbot
sudo apt install nginx certbot python3-certbot-nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx

# Weryfikacja
docker --version
docker compose version
```

---

## Etap 4: Otwieranie portów (Firewall GCP)

GCP ma **dwa poziomy** firewalla: VM (ufw) i sieciowy (VPC). Zaznaczenie HTTP/HTTPS przy tworzeniu VM wystarczy dla portów 80/443.

Sprawdź czy ufw nie blokuje:
```bash
sudo ufw status
# Jeśli active — dodaj:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
```

---

## Etap 5: DNS + domena

### Bez domeny (tymczasowo)
Użyj External IP bezpośrednio lub `<IP>.nip.io` jako pseudo-domena do SSL.

### Z domeną
W panelu DNS (Cloudflare/Namecheap):
```
Type: A
Name: @ (lub subdomena)
Value: <EXTERNAL_IP z GCP>
TTL: Auto
```

---

## Etap 6: Nginx + SSL

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
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

# SSL
sudo certbot --nginx -d twoja-domena.com
```

---

## Etap 7: Deployment aplikacji

```bash
# Zainstaluj git
sudo apt install git -y

# Sklonuj repo (lub scp pliki)
git clone https://github.com/TWOJE_REPO/campfire.git ~/fireplace
cd ~/fireplace
```

### Zmienne środowiskowe
```bash
nano ~/fireplace/.env
```

```env
DB_HOST=db
DB_PORT=5432
DB_USER=postgres
DB_PASS=SILNE_HASLO_MIN_20_ZNAKOW
DB_NAME=chatdb

JWT_SECRET=wygeneruj_64_losowe_znaki
# openssl rand -hex 64

CLOUDINARY_CLOUD_NAME=twoj_cloud
CLOUDINARY_API_KEY=twoj_klucz
CLOUDINARY_API_SECRET=twoj_secret

ALLOWED_ORIGINS=https://twoja-domena.com
```

```bash
docker compose up -d
docker compose logs -f
```

---

## Etap 8: Flutter web build

Lokalnie (na Windowsie):
```bash
cd frontend
flutter build web --dart-define=BASE_URL=https://twoja-domena.com
```

Wgraj na serwer:
```bash
scp -r frontend/build/web/* TWOJ_USER@<IP>:~/fireplace/frontend-build/
```

Zaktualizuj Nginx config (dodaj serwowanie plików statycznych + Socket.IO proxy):

```nginx
server {
    listen 443 ssl;
    server_name twoja-domena.com;

    ssl_certificate /etc/letsencrypt/live/twoja-domena.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/twoja-domena.com/privkey.pem;

    # Flutter web (SPA)
    root /home/<TWOJ_USER>/fireplace/frontend-build;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Backend REST
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Socket.IO WebSocket
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
    return 301 https://$host$request_uri;
}
```

---

## Etap 9: Backup bazy

```bash
nano ~/backup-db.sh
```

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p ~/backups
docker exec fireplace-db-1 pg_dump -U postgres chatdb > ~/backups/chatdb_$DATE.sql
ls -t ~/backups/*.sql | tail -n +8 | xargs rm -f
```

```bash
chmod +x ~/backup-db.sh
crontab -e
# Dodaj: 0 3 * * * /home/<TWOJ_USER>/backup-db.sh
```

---

## Etap 10: Security checklist

- [ ] SSH tylko klucz (wyłącz hasła): `PasswordAuthentication no` w `/etc/ssh/sshd_config`
- [ ] Fail2ban: `sudo apt install fail2ban -y`
- [ ] JWT_SECRET min. 64 znaki, losowe (`openssl rand -hex 64`)
- [ ] ALLOWED_ORIGINS = tylko twoja domena
- [ ] `server_tokens off;` w nginx.conf
- [ ] `sudo apt update && sudo apt upgrade` regularnie

---

## Uwaga: RAM na e2-micro (1GB)

NestJS + PostgreSQL + Docker overhead może być bliski limitu. Jeśli będą problemy:

```bash
# Dodaj swap (rozszerza efektywną pamięć)
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Swap 1GB na dysku = efektywnie ~2GB pamięci. Dla 15 użytkowników wystarczy.

---

## Podsumowanie kosztów

| Składnik | Koszt |
|----------|-------|
| GCP e2-micro VM (2 vCPU, 1GB RAM) | **$0/mies** |
| 30GB Standard Persistent Disk | **$0/mies** |
| Let's Encrypt SSL | **$0** |
| Cloudinary (darmowy plan) | **$0** |
| Domena (opcjonalnie) | ~$10/rok |
| **Razem** | **$0–$10/rok** |
