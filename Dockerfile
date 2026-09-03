FROM debian:bookworm-slim

# Install dependency untuk tambah repo PGDG
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg lsb-release postgresql-client gettext-base && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        gpg --dearmor -o /usr/share/keyrings/pgdg.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends pgbouncer=1.25.2-1.pgdg12+1 && \
    apt-get purge -y curl gnupg lsb-release && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Jakarta

# Jalankan sebagai non-root user (PgBouncer sudah membuat user "postgres" secara default di paket Debian,
# tapi kita buat user khusus supaya lebih eksplisit dan terisolasi dari nama umum)
RUN groupadd -r pgbouncer && useradd -r -g pgbouncer -d /etc/pgbouncer pgbouncer && \
    mkdir -p /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer && \
    chown -R pgbouncer:pgbouncer /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer

# Copy config template dan entrypoint
COPY pgbouncer.ini.template /etc/pgbouncer/pgbouncer.ini.template
COPY userlist.txt.template /etc/pgbouncer/userlist.txt.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown pgbouncer:pgbouncer /etc/pgbouncer/*.template

USER pgbouncer
EXPOSE 6432

# pg_isready dipilih karena cuma mengecek server merespons handshake protokol —
# TIDAK butuh auth berhasil. psql -c "SHOW VERSION" butuh login sukses ke database
# admin "pgbouncer" (hanya boleh admin_users/stats_users), dan password di env kita
# (AUTH_PASSWORD dkk) sudah dalam bentuk hash untuk userlist.txt, bukan plaintext —
# jadi tidak bisa dipakai langsung sebagai PGPASSWORD untuk login.
# Pakai ADMIN_USER (bukan AUTH_USER) supaya lolos ACL admin_users di db "pgbouncer" —
# pg_isready tetap tidak pernah kirim password, tapi log tidak dipenuhi WARNING
# "not allowed" tiap interval karena user ditolak masuk pseudo-db admin.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pg_isready -h 127.0.0.1 -p 6432 -U "${ADMIN_USER}" -d pgbouncer

ENTRYPOINT ["/entrypoint.sh"]
