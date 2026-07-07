#!/bin/bash

set -Eeuo pipefail

BACKUP_ROOT="/mnt/backup"
HOMELAB_DIR="/home/ashutosh/homelab"
DATE=$(date +"%Y-%m-%d")
DB_BACKUP_DIR="$BACKUP_ROOT/db/$DATE"

# Load secrets (DB passwords) from the same .env the stack uses — no hardcoding.
if [ -f "$HOMELAB_DIR/.env" ]; then
  set -a
  . "$HOMELAB_DIR/.env"
  set +a
fi
SEAFILE_ROOT_PW="${INIT_SEAFILE_MYSQL_ROOT_PASSWORD:-}"
PG_PASS="${PG_PASS:-postgres}"

log() {
echo "[$(date '+%F %T')] $*"
}

log "=============== Backup Started ================"

# Verify backup disk is mounted

mountpoint -q "$BACKUP_ROOT" || {
log "ERROR: Backup disk is not mounted"
exit 1
}

# Verify backup disk is writable

touch "$BACKUP_ROOT/.backup-test" || {
log "ERROR: Backup disk is not writable"
exit 1
}
rm -f "$BACKUP_ROOT/.backup-test"

mkdir -p "$DB_BACKUP_DIR"

########################################

# Database Backups

########################################

log "Backing up Immich PostgreSQL"

docker exec immich_postgres pg_dump -U postgres immich > "$DB_BACKUP_DIR/immich.sql"

log "Backing up Seafile MariaDB"

docker exec seafile-mysql mysqldump -uroot -p"$SEAFILE_ROOT_PW" --all-databases > "$DB_BACKUP_DIR/seafile.sql"

log "Backing up shared PostgreSQL (Linkwarden etc.)"

docker exec -e PGPASSWORD="$PG_PASS" postgres pg_dumpall -U postgres > "$DB_BACKUP_DIR/postgres.sql"

########################################

# Navidrome Backup

########################################

log "Backing up Navidrome"

docker exec navidrome /app/navidrome backup create || true

rsync -a --info=progress2 --delete "$HOMELAB_DIR/navidrome/backup/" "$BACKUP_ROOT/navidrome/backup/"

########################################

# Application Data

########################################

log "Backing up Immich"

rsync -a --delete /mnt/primary/immich/ "$BACKUP_ROOT/immich/"

log "Backing up Seafile"

rsync -a --delete /mnt/primary/seafile/ "$BACKUP_ROOT/seafile/"

########################################

# User Data

########################################

log "Backing up Photos"

rsync -a --delete /mnt/primary/Photos/ "$BACKUP_ROOT/Photos/"

log "Backing up Documents"

rsync -a --delete /mnt/primary/Documents/ "$BACKUP_ROOT/Documents/"

########################################

# Infrastructure Config

########################################

log "Backing up Docker Compose files"

rsync -a --delete "$HOMELAB_DIR/" "$BACKUP_ROOT/homelab-config/"

# System config — guarded so a missing path (e.g. Caddy lives on the VPS) does
# not abort the whole run under `set -e`.
if [ -d /etc/wireguard ]; then
  log "Backing up WireGuard"
  sudo rsync -a /etc/wireguard/ "$BACKUP_ROOT/system/wireguard/"
fi

if [ -d /var/apps/docker/caddy ]; then
  log "Backing up Caddy"
  sudo rsync -a /var/apps/docker/caddy/ "$BACKUP_ROOT/system/caddy/"
fi

########################################

# Cleanup old DB dumps

########################################

find "$BACKUP_ROOT/db" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +

log "=============== Backup Finished ================"
