# 🧰 Basic Homelab Setup

This repository contains the complete configuration for a **self-hosted homelab** running on a Linux host using Docker Compose, with a **two-disk storage model** and **verified nightly backups**.

It provides:

* Photo management (Immich)
* Media streaming (Plex)
* Personal cloud storage (Seafile)
* Calendar & contacts (Radicale)
* Reverse proxy (NGINX)
* Full data redundancy via rsync-based backups

The system is designed to be **safe against accidental data loss**, **power failures**, and **disk unplug events**.

---

## 🧱 Architecture

```
                ┌──────────────────────┐
                │   Linux Host OS       │
                │  /home/myuser (SSD) │
                └──────────┬───────────┘
                           │
                    docker-compose
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
┌───────▼────────┐                    ┌───────▼────────┐
│ /mnt/primary   │                    │ /mnt/backup    │
│ 2.5" HDD       │                    │ USB HDD        │
│ (Live data)   │                    │ (Backups)     │
└────────────────┘                    └────────────────┘
```

| Layer           | Purpose                   |
| --------------- | ------------------------- |
| **SSD**         | OS, Docker, configs, logs |
| **Primary HDD** | All live service data     |
| **Backup HDD**  | Nightly rsync mirror      |

---

## 💽 Disk Layout

Defined in `/etc/fstab`:

| Mount          | Purpose          | Options               |
| -------------- | ---------------- | --------------------- |
| `/`            | OS               | ext4                  |
| `/mnt/primary` | All homelab data | ext4, noatime         |
| `/mnt/backup`  | Backup drive     | ext4, noatime, nofail |

The backup disk is allowed to be unplugged (`nofail`) without breaking boot.

---

## 🐳 Services

All services run in a single Docker Compose stack:

| Service    | Purpose          | Storage                          |
| ---------- | ---------------- | -------------------------------- |
| Immich     | Photo management | `/mnt/primary/immich`            |
| PostgreSQL | Immich DB        | `/mnt/primary/immich/db`         |
| Plex       | Media server     | `/mnt/primary/Movies`, `/Series` |
| Seafile    | Personal cloud   | `/mnt/primary/seafile`           |
| MariaDB    | Seafile DB       | `/mnt/primary/seafile/mysql`     |
| Radicale   | CalDAV / CardDAV | `/mnt/primary/radicale`          |
| Redis      | Immich cache     | ephemeral                        |
| NGINX      | Reverse proxy    | SSD                              |

Plex runs in `host` mode for DLNA and Chromecast compatibility.

---

## 📂 Directory Layout

```
/mnt/primary
├── immich/
│   ├── library
│   └── db.sql
├── seafile/
│   ├── shared
│   └── db.sql
├── radicale/
├── Movies/
├── Series/
└── torrents/
```

Backup mirrors the same structure under `/mnt/backup`.

---

## 🔁 Backup Strategy

A **nightly 3am cron job** performs a safe, atomic backup:

### 1. Safety check

Backup aborts unless the backup disk is mounted:

```bash
findmnt /mnt/backup || exit 1
```

This prevents rsync from writing to `/mnt/backup` when the USB disk is unplugged.

---

### 2. Database dumps

Databases are dumped live from containers:

| App     | Command     |
| ------- | ----------- |
| Immich  | `pg_dump`   |
| Seafile | `mysqldump` |

They are written into `/mnt/primary` so they are also backed up.

---

### 3. Rsync mirror

Data is copied using:

```
rsync -avp
```

This preserves:

* Ownership
* Permissions
* Timestamps
* Symlinks

Result:

```
/mnt/backup == complete mirror of /mnt/primary
```

---

## ⏰ Cron

Runs daily at 03:00:

```
0 3 * * * /home/myuser/homelab/backup.sh >> /home/myuser/backup.log 2>&1
```

Logs allow forensic verification of every backup run.

---

## 🛡 Data Safety Guarantees

This system prevents all common failure modes:

| Risk              | Protection                       |
| ----------------- | -------------------------------- |
| USB unplugged     | Backup aborts                    |
| Power failure     | Journaling FS + idempotent rsync |
| Corrupt DB        | Logical SQL dumps                |
| Docker bug        | Data stored outside containers   |
| Accidental delete | Backup mirror                    |

---

## 🌐 Network

All containers run on:

```
homelab_net (Docker bridge)
```

Plex uses host networking to allow DLNA discovery.

---

## 🧠 Design Philosophy

This homelab is designed like a **small system**:

* **Stateless containers**
* **Stateful volumes on real disks**
* **Crash-safe backups**
* **Mount-verified writes**
* **No single point of silent failure**

It behaves more like a NAS + application cluster than a hobby setup.

---

## 🚀 Starting the stack

From `/home/myuser/homelab`:

```
docker compose up -d
```

---

## 🧪 Verify backup disk

```
findmnt /mnt/backup
```

Must show a mounted filesystem before running backups.

---

## 🧾 Restore example

Restore Immich photos:

```
rsync -av /mnt/backup/immich/ /mnt/primary/immich/
```

Restore database:

```
docker exec -i immich_postgres psql -U postgres immich < db.sql
```

---

## 🏁 TODO

* Wireguard Tunnel Setup
* Disaster recovery

* adding snapshotting (btrfs or zfs)
* or off-site encrypted sync to cloud / another machine
