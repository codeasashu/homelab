## Homelab Setup

### Prerequisites

- Linux OS (I am using endavourOS)
- Docker (with docker-compose)

### 1. Setting up external harddrive mounting

Find UUID of external device (follow https://linuxvox.com/blog/how-to-mount-an-exfat-drive-on-ubuntu-linux/#method-3-mounting-exfat-drive-automatically-on-startup)
```sh
sudo blkid
```

Then, Add UUID in fstab (See fstab file attached)

### 2. Starting Jellyfin

```sh
# 1. create 'services' dir in $HOME
mkdir -p ~/services/jellyfin

# 2. Move the attached docker-compose of jellyfin to services dir
mv docker-compose.yml ~/services/jellyfin/

# 3. Start jellyfin
cd ~/services/jellyfin/; docker-compose up -d
```
