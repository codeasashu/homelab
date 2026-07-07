# 🧰 Homelab

Docker Compose configuration for a self-hosted homelab running on a single
Linux host, with a **two-disk storage model**, **LAN-first access**, and
**layered backups**.

> This README is the intent/overview. The source of truth for what actually
> runs is [`docker-compose.yml`](./docker-compose.yml); operational details are
> in [`CLAUDE.md`](./CLAUDE.md).

---

## 🖥 Host

Toshiba Satellite C850 laptop, Ubuntu Server — 2 cores / 4 threads, **8 GB RAM**
(the binding constraint), Intel HD 4000 iGPU passed to Jellyfin (`/dev/dri`) for
hardware transcode. It runs ~20 containers, so be conservative adding services
or raising memory / `shm_size`.

---

## 🌐 Access model

The host has a **static LAN IP `192.168.1.12`** (router DHCP reservation).

- **Daily driver — LAN by IP:** `http://192.168.1.12:<port>`. Fastest path for
  bandwidth-heavy use (Jellyfin, Immich) since the server is on the same LAN.
- **Remote — Tailscale:** host-level Tailscale for occasional off-site access to
  Immich / Seafile / Navidrome. No per-container VPN config.
- **Canonical identity — owned domain `codeasashu.in.eu.org`:** used for
  origin-bound services (pocket-id passkeys, Jellyfin, Seafile). Because the
  domain is owned, it's stable across Tailscale/Headscale renames; point it at
  the LAN IP / a VPS / Headscale via DNS without editing compose.

All host/identity values (`LAN_IP`, `PUBLIC_DOMAIN`, `TAILNET_SUFFIX`, `TZ`,
`PUID`/`PGID`) are `.env` variables with defaults baked into compose — switching
transport is a one-line `.env` edit, not a compose change.

> Historical note: public access was previously fronted by an Oracle "always
> free" VPS running Caddy over a WireGuard tunnel (see the `vps` branch and
> `vps/`). That path is being retired in favour of Tailscale; the compose no
> longer references the `10.66.66.2` tunnel IP.

---

## 💽 Storage

Defined in [`fstab`](./fstab):

| Mount          | Disk            | Holds                                   |
| -------------- | --------------- | --------------------------------------- |
| `/`            | NVMe SSD        | OS, Docker, this repo, container configs |
| `/mnt/primary` | 1 TB 2.5" HDD   | All live service **data**               |
| `/mnt/backup`  | USB HDD (`nofail`) | Backup target (safe to unplug)       |

Data lives **outside containers** so a container/image change never risks it:
- **config** → `./<svc>` on the SSD (bind-mounted into containers)
- **bulk data** → `/mnt/primary/...`

---

## 🐳 Services

Single Compose stack on the `homelab_net` bridge (services reach each other by
name). Public ports on the host:

| Service                 | Port  | Purpose                          |
| ----------------------- | ----- | -------------------------------- |
| Homepage                | 3000  | Dashboard                        |
| Uptime-Kuma             | 3001  | Monitoring                       |
| nginx                   | 80    | LAN reverse proxy (`*.homelab.lan`) |
| Immich                  | 2283  | Photos (own Postgres + Redis)    |
| Seafile                 | 8081  | Files/cloud (MariaDB)            |
| Navidrome               | 4533  | Music                            |
| Jellyfin                | 8096  | Movies / TV (HW transcode)       |
| Sonarr                  | 8989  | TV automation                    |
| Radarr                  | 7878  | Movie automation                 |
| qBittorrent             | 8080  | Downloads                        |
| Linkwarden              | 3002  | Bookmarks (shared Postgres + Meilisearch) |
| Calibre-Web-Automated   | 8083  | E-books                          |
| pocket-id               | 1411  | SSO / passkeys (OIDC)            |
| Backrest                | 9898  | restic backups                   |

**Two separate Postgres instances** (don't confuse them):
`immich_postgres` (pgvector, Immich only) and the generic `postgres`
(16-alpine, shared by Linkwarden; DBs created via `./postgres/init`).

There is **no Plex** (Jellyfin replaced it) and **no Radicale**.

---

## ⚙️ Configuration

- Copy [`.env.example`](./.env.example) → `.env` (gitignored) and fill in.
  It documents every `${VAR}` the compose reads.
- Start / operate:

```bash
docker compose up -d
docker compose logs -f <service>
docker compose restart <service>
docker compose config          # lint before bringing up
```

---

## 🔁 Backups (two layers)

1. **Backrest** (container, port 9898) — restic repo at `/mnt/backup/restic`
   (`RESTIC_PASSWORD`). Snapshots read-only mounts of Immich, Memories, Books,
   docs, Seafile and the homelab config dir. Handles file-level app data,
   dedup, and retention.

2. **`backup2.sh`** (nightly cron) — the piece Backrest can't safely do:
   **logical database dumps** (Immich `pg_dump`, Seafile `mysqldump`, shared
   Postgres `pg_dumpall`, Navidrome dump) into `/mnt/backup/db/<date>/` with
   30-day rotation, plus `rsync --delete` of Immich/Seafile/Photos/Documents and
   the homelab config. Guards: aborts unless `/mnt/backup` is mounted **and**
   writable. Secrets are read from `.env` (not hardcoded).

> `backup.sh` (legacy rsync-only script) has been removed — superseded by the
> two layers above.

Example cron (verify the target before relying on it):

```
0 3 * * * /home/ashutosh/homelab/backup2.sh >> /home/ashutosh/backup.log 2>&1
```

### Restore examples

```bash
# Immich DB (from a dated dump)
docker exec -i immich_postgres psql -U postgres immich < /mnt/backup/db/<date>/immich.sql

# Immich files
rsync -a /mnt/backup/immich/ /mnt/primary/immich/
```

---

## 🗂 Git tracking

Only source config is tracked (compose, `.env.example`, `nginx/conf.d/`,
`postgres/init/`, `homepage/` YAML, `backup2.sh`, `fstab`, `smb.conf`). All
service **runtime-state** dirs (databases, caches, sqlite, API-key configs,
passkeys) are gitignored — see [`.gitignore`](./.gitignore). Bulk data on
`/mnt/primary` is outside the repo entirely.

---

## 🏁 TODO

- Decommission the Oracle VPS / WireGuard tunnel once Tailscale (or Headscale)
  fully covers remote access.
- Reconcile Backrest's `RESTIC_REPOSITORY` (`/backup/restic`) with its volume
  mount (`/mnt/backup:/repos`).
- Snapshotting (btrfs/zfs) and/or off-site encrypted sync.
