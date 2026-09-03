# pgbouncer-image

Docker image [PgBouncer](https://www.pgbouncer.org/) siap-produksi, dikonfigurasi untuk beban platform PPOB
(banyak koneksi pendek — cek pulsa, bayar PLN, dll). Konfigurasi di-generate saat container start dari
environment variable, sehingga image yang sama bisa dipakai untuk beberapa environment (dev/staging/prod)
tanpa membangun ulang image.

## Fitur

- Base image `debian:bookworm-slim` + PgBouncer dari repo resmi PGDG (versi dipin: `1.25.2-1.pgdg12+1`).
- Berjalan sebagai non-root user (`pgbouncer`).
- Konfigurasi (`pgbouncer.ini`, `userlist.txt`) di-generate dari template (`*.template`) via `envsubst`
  saat container start — lihat [entrypoint.sh](entrypoint.sh).
- `HEALTHCHECK` bawaan pakai `pg_isready` (cek server hidup tanpa perlu login berhasil).
- Validasi environment variable wajib saat start — container gagal cepat (fail-fast) dengan pesan jelas
  kalau ada yang belum diisi, alih-alih silent error di config.
- CI: build & push image ke GHCR ([.github/workflows/build-and-push.yml](.github/workflows/build-and-push.yml))
  dan scan kerentanan dengan Trivy ([.github/workflows/scan.yml](.github/workflows/scan.yml)).

## Struktur file

| File | Keterangan |
|---|---|
| [Dockerfile](Dockerfile) | Build image: install PgBouncer, buat user non-root, set healthcheck. |
| [entrypoint.sh](entrypoint.sh) | Validasi env var, resolve default, generate config dari template, jalankan PgBouncer. |
| [pgbouncer.ini.template](pgbouncer.ini.template) | Template konfigurasi utama PgBouncer. |
| [userlist.txt.template](userlist.txt.template) | Template daftar user & password (hash) untuk autentikasi. |
| [docker-compose.yml](docker-compose.yml) | Compose untuk build & jalankan image secara lokal/testing. |
| [.env.template](.env.template) | Contoh environment variable — copy jadi `.env` dan isi nilai asli. |

## Menjalankan (lokal/testing)

```bash
# 1. Siapkan environment variable
cp .env.template .env
# ...edit .env, isi minimal DB_HOST, DB_PORT, DB_NAME, AUTH_USER, AUTH_PASSWORD

# 2. Build & jalankan
docker compose up -d --build

# 3. Cek status & log
docker compose ps
docker compose logs -f pgbouncer
```

PgBouncer akan listen di `localhost:6432`.

## Environment variable

### Wajib

Tidak punya default yang aman — container akan langsung berhenti dengan error kalau kosong.

| Variable | Keterangan |
|---|---|
| `DB_HOST` | Host PostgreSQL tujuan. |
| `DB_PORT` | Port PostgreSQL tujuan. |
| `DB_NAME` | Nama database yang di-proxy. |
| `AUTH_USER` | User aplikasi untuk autentikasi ke PgBouncer. |
| `AUTH_PASSWORD` | Password `AUTH_USER`, format mengikuti `AUTH_TYPE` (lihat di bawah). |

### Opsional (punya default)

| Variable | Default | Keterangan |
|---|---|---|
| `AUTH_TYPE` | `md5` | Metode autentikasi PgBouncer. |
| `ADMIN_USER` | `pgbouncer_admin` | User untuk admin console PgBouncer. |
| `ADMIN_PASSWORD` | *(kosong)* | Password admin — wajib diisi untuk login ke admin console. |
| `STATS_USER` | `pgbouncer_stats` | User read-only untuk melihat statistik. |
| `STATS_PASSWORD` | *(kosong)* | Password `STATS_USER`. |
| `POOL_MODE` | `transaction` | Mode pooling PgBouncer. |
| `MAX_CLIENT_CONN` | `500` | Total koneksi dari aplikasi ke PgBouncer. |
| `DEFAULT_POOL_SIZE` | `25` | Koneksi aktual ke PostgreSQL per pasangan database/user. |
| `MIN_POOL_SIZE` | `5` | Jumlah koneksi minimum yang dijaga tetap terbuka. |
| `RESERVE_POOL_SIZE` | `5` | Koneksi cadangan saat pool utama penuh. |
| `CLIENT_TLS_SSLMODE` | `disable` | TLS untuk koneksi aplikasi → PgBouncer. Kalau diisi selain `disable`, `CLIENT_TLS_CERT` dan `CLIENT_TLS_KEY` wajib diisi juga. |
| `CLIENT_TLS_CERT` / `CLIENT_TLS_KEY` | *(kosong)* | Path sertifikat/key TLS sisi client (di dalam container). |
| `SERVER_TLS_SSLMODE` | `require` | TLS untuk koneksi PgBouncer → PostgreSQL. |

**Format password** (`AUTH_PASSWORD`, `ADMIN_PASSWORD`, `STATS_PASSWORD`) untuk `AUTH_TYPE=md5`:

```bash
echo -n "<password><username>" | md5sum
# hasilnya diawali "md5" saat ditulis ke userlist.txt, contoh: md5xxxxxxxx...
```

Lihat [.env.template](.env.template) untuk contoh lengkap semua variable.

## CI/CD

- **build-and-push** — jalan tiap push ke `main` atau tag `v*`; build image dan push ke
  `ghcr.io/<owner>/<repo>`.
- **scan** — jalan tiap push/PR ke `main` dan terjadwal tiap Senin; scan image dengan
  [Trivy](https://github.com/aquasecurity/trivy) dan upload hasilnya ke tab *Security* GitHub
  (tidak menggagalkan build meski ada temuan CRITICAL/HIGH — ubah `exit-code` di
  [scan.yml](.github/workflows/scan.yml) kalau mau lebih ketat).

## Keamanan

- `.env` (kredensial asli) **tidak** ikut di-commit — lihat [.gitignore](.gitignore).
- `userlist.txt` hasil generate diberi permission `600` (lihat `entrypoint.sh`) karena berisi
  hash password.
- Container berjalan sebagai user non-root (`pgbouncer`).
- Password disimpan dalam bentuk hash (`md5`/SCRAM), bukan plaintext, di `userlist.txt`.
