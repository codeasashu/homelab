#!/bin/bash

set -euo pipefail

echo '=============== Backup Started ================'

sudo findmnt -rno TARGET /mnt/backup >/dev/null || {
    echo "Backup disk not mounted"
    exit 1
}

# Container Backups
echo 'executing: docker exec immich_postgres pg_dump -U postgres immich > /mnt/primary/immich/db.sql'
docker exec immich_postgres pg_dump -U postgres immich > /mnt/primary/immich/db.sql
echo 'executing: docker exec seafile-mysql mysqldump -uroot -pdb_dev --all-databases > /mnt/primary/seafile/db.sql'
docker exec seafile-mysql mysqldump -uroot -pdb_dev --all-databases > /mnt/primary/seafile/db.sql
echo 'docker exec navidrome /app/navidrome backup create'
docker exec navidrome /app/navidrome backup create
sudo rsync -avp --info=progress2 /home/ashutosh/homelab/navidrome/backup/ /mnt/backup/navidrome/backup/

# Media Backups
echo 'executing: rsync -avp --info=progress2 /mnt/primary/immich/ /mnt/backup/immich/'
rsync -avp --info=progress2 /mnt/primary/immich/ /mnt/backup/immich/
echo 'executing: rsync -avp --info=progress2 /mnt/primary/seafile/ /mnt/backup/seafile/'
rsync -avp --info=progress2 /mnt/primary/seafile/ /mnt/backup/seafile/
echo 'executing: rsync -avp --info=progress2 /mnt/primary/radicale/ /mnt/backup/radicale/'
rsync -avp --info=progress2 /mnt/primary/radicale/ /mnt/backup/radicale/
echo 'executing: rsync -avp --info=progress2 /mnt/primary/Movies/ /mnt/backup/Movies/'
rsync -avp --info=progress2 /mnt/primary/Movies/ /mnt/backup/Movies/
echo 'executing: rsync -avp --info=progress2 /mnt/primary/Series/ /mnt/backup/Series/'
rsync -avp --info=progress2 /mnt/primary/Series/ /mnt/backup/Series/
echo '=============== Backup Finished ================'
