#!/bin/bash

set -euo pipefail

sudo findmnt -rno TARGET /mnt/backup >/dev/null || {
    echo "Backup disk not mounted"
    exit 1
}

# Dump DB
docker exec immich_postgres pg_dump -U postgres immich > /mnt/primary/immich/db.sql
docker exec seafile-mysql mysqldump -uroot -pdb_dev --all-databases > /mnt/primary/seafile/db.sql

rsync -avp --info=progress2 /mnt/primary/immich/ /mnt/backup/immich/
rsync -avp --info=progress2 /mnt/primary/seafile/ /mnt/backup/seafile/
rsync -avp --info=progress2 /mnt/primary/radicale/ /mnt/backup/radicale/
rsync -avp --info=progress2 /mnt/primary/Movies/ /mnt/backup/Movies/
rsync -avp --info=progress2 /mnt/primary/Series/ /mnt/backup/Series/
