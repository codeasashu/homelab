# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Configuration (not application code) for a self-hosted homelab. There is nothing to build, lint, or test — changes are deployed by editing config and restarting containers. Everything is driven by Docker Compose.

## Hardware & network topology

**Home server (Toshiba Satellite C850 laptop, Ubuntu Server):**
- CPU: Intel Core i5-3210M (Ivy Bridge) — **2 cores / 4 threads**, 2.5 GHz base / 3.1 GHz turbo. iGPU is Intel HD 4000, which is why Jellyfin gets `/dev/dri` (QSV hardware transcode, but a weak/old GPU — expect limits on 4K/HEVC).
- RAM: **8 GB** (the binding constraint — see below).
- Disks: 256 GB NVMe SSD (via adapter) = `/` (OS, Docker, configs); 1 TB internal 2.5" HDD in the DVD caddy = `/mnt/primary` (live data); 1 TB external HDD = `/mnt/backup`.

**This is a resource-constrained host.** 2 cores / 8 GB RAM run ~20 containers including two Postgres instances, Immich ML, Authentik (server+worker, `shm_size: 512mb` each), Meilisearch, and Jellyfin transcoding. Be conservative when adding services or raising memory/`shm_size`; prefer scheduling heavy jobs (ML, backups) off-peak.

**Network path (explains the VPS tunnel):**
- JioFiber is the primary router (ground floor) and is **behind CG-NAT** — no public inbound IP, so the home server *cannot* be reached directly from the internet. This is the entire reason public services are fronted by the Oracle VPS over WireGuard rather than a port-forward.
- A TP-Link secondary router (OpenWrt, first floor) connects to the JioFiber router **as a Wi-Fi client**; the Toshiba is on the OpenWrt LAN. So the home server sits two NATs deep.
- **Oracle Cloud "always free" VPS** (single compute instance) holds the public IP and runs only Caddy.
- Domain `codeasashu.in.eu.org` (lifetime-free) is on Cloudflare free tier; `*.codeasashu.in.eu.org` resolves to the VPS.
- The Caddy allowlist IP `146.56.50.117` (`@blocked not remote_ip ...`) is a *trusted client* address, not the VPS's own IP — confirm what it is before relying on it (note: behind CG-NAT the home IP is not a stable allowlist candidate).

**Goals driving the design:**
- Publicly expose primarily **Immich, Jellyfin, Linkwarden, Calibre-Web** (matches the Caddy hostnames; note Calibre-Web/8083 is not yet proxied publicly).
- **Single SSO** (Authentik) in front of public services.
- **LAN-first**: the user is usually home (WFH) and prefers private/LAN access; remote access matters only ~1–2 trips/month. So LAN paths (`*.homelab.lan` via nginx, direct host IP) are the common case, not the public path.
- **DDoS protection** is a goal — the Caddy IP-allowlist (`@blocked`) and Cloudflare proxying are the levers here.

## Two deployment targets

This repo configures **two separate hosts**, and the layout maps to git branches:

- **Home server** — root of the repo (`docker-compose.yml`, `nginx/`, `backup.sh`, `backup2.sh`, `smb.conf`, `fstab`). Runs all the actual services. Tracked on `main`.
- **Public VPS** — `vps/` directory (`vps/docker-compose.yml`, `vps/caddy/Caddyfile`). Runs only Caddy. Lives on the `vps` branch (not present on `main` — use `git show vps:vps/caddy/Caddyfile` to read it).

The two are linked by a **WireGuard tunnel**: the VPS's Caddy reverse-proxies public hostnames (`*.codeasashu.in.eu.org`) to the home server at its tunnel IP `10.66.66.2`. So a new home service that should be public requires changes in **both** places — expose the port in `docker-compose.yml` *and* add a `reverse_proxy 10.66.66.2:<port>` block in `vps/caddy/Caddyfile`.

Caddy blocks every IP except `146.56.50.117` for most hostnames via `@blocked not remote_ip 146.56.50.117` → `respond @blocked 403`. **`media` (Jellyfin) is the sole fully-public host** — it has no `@blocked` guard. Keep the allowlist guard when adding new proxied hosts unless the service is meant to be open. Current public hostnames: `home`→3000, `uptime`→3001, `photos`→2283, `music`→4533, `files`→8081, `media`→8096.

## Deploy / run commands

```bash
# Home server (from repo root)
docker compose up -d
docker compose logs -f <service>
docker compose restart <service>

# VPS (on the vps branch / host)
docker compose -f vps/docker-compose.yml up -d
```

Requires a `.env` file (gitignored). `.env.example` only covers the Immich vars — the compose file references **more secrets that are not in the example**: `PG_PASS` (shared Postgres), `RESTIC_PASSWORD` (Backrest), `AUTHENTIK_SECRET_KEY` / `AUTHENTIK_TAG`, and `HOMEPAGE_JELLYFIN_API_KEY`. When adding a service that reads `${VAR}`, also document it. Note Seafile/MariaDB secrets and the Seafile admin login are **hardcoded in `docker-compose.yml`** (`db_dev`, `admin@localhost` / `asecret`), not in `.env`.

## Services (what's actually deployed)

The README service table is the *intended* design and drifts from reality. Trust `docker-compose.yml`. As of now it runs:

- **Media**: Jellyfin (8096, movies/TV — uses `/dev/dri` for hardware transcode), Navidrome (4533, music). **There is no Plex** — `nginx/conf.d/plex.conf.bkp` is a dead backup. No container uses `network_mode: host`; everything is on the `homelab_net` bridge.
- **Photos/files**: Immich (2283; has its **own** Postgres + Redis), Seafile (8081; MariaDB + memcached).
- **Automation (\*arr stack)**: Sonarr (8989), Radarr (7878), qBittorrent (8080). All mount `/mnt/primary` as `/data`.
- **Auth/identity**: Authentik SSO (`authentik-server` on 9000 + `authentik-worker`), backed by the **shared** Postgres.
- **Apps**: Linkwarden (3002, bookmarks; needs Postgres + Meilisearch), Calibre-Web (8083), Meilisearch.
- **Infra**: Homepage dashboard (3000), Uptime-Kuma (3001), nginx (80, LAN reverse proxy), Backrest (9898, restic backups).

**Two separate Postgres instances exist** — don't confuse them: `immich_postgres` (pgvector image, Immich only) and the generic `postgres` (16-alpine, shared by Authentik + Linkwarden, creates DBs via `./postgres/init`). Homepage service labels (`homepage.group`, `homepage.icon`, etc.) drive the dashboard; add them when adding a service you want listed.

## Storage model (critical for data safety)

- **SSD (`/`)**: OS, Docker, this repo, container *configs*. Most volume mounts are relative (`./jellyfin/config`, `./seafile/mysql`, `./authentik/...`, `./postgres/data`, `./sonarr`, etc.) and live here.
- **`/mnt/primary`** (HDD): all live service *data* — Immich library, Seafile `shared`, Movies, Series, Music, Downloads, Photos, Documents, Books. Service data volumes point here, not into containers.
- **`/mnt/backup`** (USB HDD, `nofail`): backup target. May be unplugged without breaking boot.

Mounts are defined in `fstab` (copy of `/etc/fstab`). Data is deliberately stored outside containers so a container/image change never risks the data. When adding a stateful service, decide deliberately: config → `./<svc>` (SSD), bulk data → `/mnt/primary`.

## Backups (three overlapping mechanisms — know which is live)

1. **`backup2.sh`** (newer, preferred): guards on `mountpoint` + a writability test; dumps Immich (`pg_dump`) and Seafile (`mysqldump`) into **`/mnt/backup/db/$DATE/`** with **30-day rotation**; `rsync -a --delete` for immich/seafile/radicale/Photos/Documents; also backs up the **homelab config dir, `/etc/wireguard`, and Caddy config**. Uses `--delete`, so removed source files are removed from backup.
2. **`backup.sh`** (legacy): guards on `findmnt`; dumps DBs **into `/mnt/primary`** (so they get mirrored), then `rsync -avp` (no `--delete`) immich/seafile/radicale/Movies/Series. Still references Radicale even though it's no longer a running container.
3. **Backrest container** (9898): restic-based, repo at `/mnt/backup/restic` (`RESTIC_PASSWORD`), snapshots read-only mounts of immich/Memories/Books/docs/seafile + the homelab dir.

Cron historically runs a backup at 03:00 (`0 3 * * * .../backup.sh >> backup.log 2>&1`); confirm which script the active crontab points at before editing. When you add a new stateful service, add its data dir to the rsync list in the active script (and a DB dump step if it has a database).

## Networking notes

- Home containers share the `homelab_net` bridge network and reach each other by service name (e.g. `immich-server:2283`, `postgres:5432`).
- Home `nginx` (port 80) does LAN-side reverse proxying for `*.homelab.lan` (configs in `nginx/conf.d/`); the VPS Caddy handles public access. These are independent layers — a service can be on one, both, or neither.
