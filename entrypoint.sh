#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/pgbouncer"

# --- Validasi environment variable WAJIB (tidak punya nilai default yang aman) ---
required_vars=(DB_HOST DB_PORT DB_NAME AUTH_USER AUTH_PASSWORD)
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Environment variable ${var} wajib diisi." >&2
        exit 1
    fi
done

# --- Nilai default untuk variable OPSIONAL ---
# PENTING: envsubst TIDAK memahami syntax ${VAR:-default} di dalam file template —
# ia hanya mengganti ${VAR} dengan isi environment variable apa adanya. Kalau VAR
# kosong/tidak di-set, hasilnya string kosong, BUKAN nilai default, dan kalau
# template ditulis literal "${VAR:-default}" itu akan lolos apa adanya ke config
# lalu bikin PgBouncer gagal start ("invalid value" seperti error yang Tuan alami).
# Solusinya: nilai default di-resolve di sini oleh BASH (export biasa mendukung
# syntax ini), BUKAN di dalam file .template. Template cukup pakai ${VAR} polos.
export AUTH_TYPE="${AUTH_TYPE:-md5}"
export ADMIN_USER="${ADMIN_USER:-pgbouncer_admin}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
export STATS_USER="${STATS_USER:-pgbouncer_stats}"
export STATS_PASSWORD="${STATS_PASSWORD:-}"
export POOL_MODE="${POOL_MODE:-transaction}"
export MAX_CLIENT_CONN="${MAX_CLIENT_CONN:-500}"
export DEFAULT_POOL_SIZE="${DEFAULT_POOL_SIZE:-25}"
export MIN_POOL_SIZE="${MIN_POOL_SIZE:-5}"
export RESERVE_POOL_SIZE="${RESERVE_POOL_SIZE:-5}"
# client_tls_sslmode selain "disable" WAJIB punya client_tls_cert_file dan
# client_tls_key_file terisi (PgBouncer bertindak sebagai TLS server ke client).
# Default "disable" karena koneksi client -> pgbouncer biasanya lewat jaringan
# internal Docker; kalau mau TLS di sisi client, set CLIENT_TLS_SSLMODE eksplisit
# (require/verify-ca/verify-full) SEKALIGUS CLIENT_TLS_CERT dan CLIENT_TLS_KEY.
export CLIENT_TLS_SSLMODE="${CLIENT_TLS_SSLMODE:-disable}"
export CLIENT_TLS_CERT="${CLIENT_TLS_CERT:-}"
export CLIENT_TLS_KEY="${CLIENT_TLS_KEY:-}"

if [ "$CLIENT_TLS_SSLMODE" != "disable" ] && { [ -z "$CLIENT_TLS_CERT" ] || [ -z "$CLIENT_TLS_KEY" ]; }; then
    echo "ERROR: CLIENT_TLS_SSLMODE=${CLIENT_TLS_SSLMODE} tapi CLIENT_TLS_CERT/CLIENT_TLS_KEY kosong." >&2
    echo "       Isi keduanya, atau set CLIENT_TLS_SSLMODE=disable." >&2
    exit 1
fi

export SERVER_TLS_SSLMODE="${SERVER_TLS_SSLMODE:-require}"

if [ -z "$ADMIN_PASSWORD" ] || [ -z "$STATS_PASSWORD" ]; then
    echo "WARNING: ADMIN_PASSWORD atau STATS_PASSWORD kosong — admin console PgBouncer" >&2
    echo "         tidak akan bisa login sampai keduanya diisi." >&2
fi

# --- Generate pgbouncer.ini dan userlist.txt dari template ---
envsubst < "${CONFIG_DIR}/pgbouncer.ini.template" > "${CONFIG_DIR}/pgbouncer.ini"
envsubst < "${CONFIG_DIR}/userlist.txt.template" > "${CONFIG_DIR}/userlist.txt"

# Permission ketat untuk userlist.txt karena berisi password
chmod 600 "${CONFIG_DIR}/userlist.txt"

echo "Config generated. Starting PgBouncer..."
exec pgbouncer "${CONFIG_DIR}/pgbouncer.ini"