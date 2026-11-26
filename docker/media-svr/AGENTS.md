# AGENTS.md — media-svr

Self-hosted media automation stack for movies and TV, run with Docker Compose.

- **Working directory:** `/home/pb/media-svr` (not a git repository)
- **Compose project / network:** `media-svr` / `media-svr_default`
- **Host:** `192.168.7.10` (LAN). Tailscale is also running on the host, but the stack does not depend on it.
- **Documented:** 2026-11-26

---

## 1. What this stack does

```
              request                   search
  Seerr  ───────────────▶  Radarr / Sonarr  ──────▶  Prowlarr
  :5055                     :7878 / :8989             :9696
                                  │
                                  │ send release
                                  ▼
                            qBittorrent :8081
                                  │
                                  │ download
                                  ▼
                            ./data/downloads
                                  │
                                  │ import (hardlink where possible)
                                  ▼
                            ./data/media/{movies,tv}
                                  │
                                  │ read-only
                                  ▼
                              Jellyfin :8096
```

- **Seerr** — user-facing request portal. Users request movies/TV; Seerr forwards approved requests to Radarr/Sonarr. Connects to Jellyfin for login and library awareness.
- **Radarr** — movie library manager. Searches indexers, sends releases to qBittorrent, imports completed downloads into `data/media/movies`.
- **Sonarr** — TV library manager. Same flow, imports into `data/media/tv`.
- **Prowlarr** — indexer manager. Holds tracker definitions and syncs them to Radarr/Sonarr as applications.
- **qBittorrent** — download client. Downloads to `data/downloads`, keeps seeding after import.
- **Jellyfin** — media server. Scans `data/media` read-only and streams/transcodes to clients.

All six containers share the default Compose network, so they can reach each other by service name: `jellyfin`, `prowlarr`, `radarr`, `sonarr`, `qbittorrent`, `seerr`.

---

## 2. Services and ports

| Service | Container | Image | Host URL | Notes |
|---|---|---|---|---|
| Jellyfin | `jellyfin` | `jellyfin/jellyfin` | http://localhost:8096 | Also UDP `7359` for autodiscovery |
| Prowlarr | `prowlarr` | `lscr.io/linuxserver/prowlarr:latest` | http://localhost:9696 | Indexers + app sync |
| Radarr | `radarr` | `lscr.io/linuxserver/radarr:latest` | http://localhost:7878 | Movies |
| Sonarr | `sonarr` | `lscr.io/linuxserver/sonarr:latest` | http://localhost:8989 | TV |
| qBittorrent | `qbittorrent` | `lscr.io/linuxserver/qbittorrent:latest` | http://localhost:8081 | WebUI on `8081`; torrent port `6881` TCP+UDP |
| Seerr | `seerr` | `ghcr.io/seerr-team/seerr:latest` | http://localhost:5055 | Has a built-in healthcheck |

All published ports bind `0.0.0.0`. There is no reverse proxy or TLS in this stack. Keep these ports on the LAN/VPN; do not expose them to the internet as-is.

`docker compose` reports the project as `media-svr`, and container names match service names.

---

## 3. Directory layout

```
media-svr/
├── compose.yaml              # Single source of truth for the stack
├── .env                      # Local values (currently same as .env.example)
├── .env.example              # Template: PUID/PGID, TZ, URLs, Seerr settings
├── data/                     # Shared media/download tree (host: pb:pb, 1000:1000)
│   ├── downloads/            # qBittorrent default save path
│   │   └── incomplete/       # qBittorrent temp path
│   └── media/
│       ├── movies/           # Radarr root folder
│       └── tv/               # Sonarr root folder
├── jellyfin/
│   ├── config/               # Jellyfin config, DB, metadata, logs (root-owned)
│   └── cache/                # Jellyfin transcode/image cache (disposable)
├── prowlarr/config/          # Prowlarr config, DB, logs
├── radarr/config/            # Radarr config, DB, logs, MediaCover
├── sonarr/config/            # Sonarr config, DB, logs, MediaCover
├── qbittorrent/config/       # qBittorrent config, BT_backup, logs
└── seerr/config/             # Seerr settings.json, SQLite DB, logs, cache
```

The per-app directories are **live bind-mounted state**, not source templates. The header comment in `compose.yaml` about "source templates" is stale; there are no template files in this checkout.

Most app config files are rewritten when the container stops. **Stop the container before hand-editing its config.** Prefer the web UI or API.

---

## 4. Path mapping (important)

| Host path | qBittorrent | Radarr / Sonarr | Jellyfin |
|---|---|---|---|
| `./data` | `/data` | `/data` | — |
| `./data/downloads` | `/data/downloads` | `/data/downloads` | — |
| `./data/media` | `/data/media` | `/data/media` | `/media` (`:ro`) |
| `./jellyfin/config` | — | — | `/config` |
| `./jellyfin/cache` | — | — | `/cache` |
| `./<app>/config` | — | `/config` | — |

Invariants:

1. Radarr, Sonarr, and qBittorrent all see the **same `./data` mount at `/data`**. This is what allows imports without path remapping.
2. qBittorrent writes to `/data/downloads`; Radarr/Sonarr import from there into `/data/media/movies` and `/data/media/tv`.
3. `./data` is one filesystem, so hardlink imports work. `copyUsingHardlinks` is enabled in both Radarr and Sonarr.
4. Jellyfin sees only `./data/media` at `/media`, read-only. It cannot see downloads, and it cannot modify media.
5. Root folders in Radarr/Sonarr are `/data/media/movies` and `/data/media/tv` — never the host paths.

If you change any of these mounts, update all affected app settings (root folders, download client paths, Jellyfin libraries, Seerr directories).

---

## 5. Setup from scratch

The stack is already configured and running. This section is for a rebuild or a new host.

### 5.1 Prerequisites

- Docker Engine and the Compose v2 plugin (`docker compose`, not `docker-compose`)
- Host user matching `PUID`/`PGID` (currently `pb`, `1000:1000`)
- Enough disk for media; the current volume has ~670 GB free

### 5.2 Configure environment

```bash
cd /home/pb/media-svr
cp .env.example .env
id -u   # set PUID
id -g   # set PGID
$EDITOR .env
```

Set `PUID`, `PGID`, `TZ`, `JELLYFIN_PUBLISHED_URL`, and Seerr values. Keep `.env` out of version control/sharing.

### 5.3 Start

```bash
docker compose config --quiet    # validate
docker compose up -d
docker compose ps
```

### 5.4 First-run app configuration (in this order)

1. **qBittorrent** (`:8081`) — set the WebUI password. Confirm default save path `/data/downloads` and temp path `/data/downloads/incomplete`. Categories `radarr` and `tv-sonarr` should exist (Radarr/Sonarr can create them).
2. **Prowlarr** (`:9696`) — add indexers, then add applications:
   - Radarr: `http://radarr:7878`, full sync
   - Sonarr: `http://sonarr:8989`, full sync
   - Prowlarr URL for both: `http://prowlarr:9696`
3. **Radarr** (`:7878`) — root folder `/data/media/movies`; download client qBittorrent at host `qbittorrent`, port `8081`, category `radarr`; media management: hardlinks enabled.
4. **Sonarr** (`:8989`) — root folder `/data/media/tv`; qBittorrent at `qbittorrent:8081`, category `tv-sonarr`.
5. **Jellyfin** (`:8096`) — add libraries Movies → `/media/movies` and Shows → `/media/tv`; set metadata language/country; add plugins as desired.
6. **Seerr** (`:5055`) — sign in with Jellyfin, then connect Radarr and Sonarr (prefer container hostnames `radarr`/`sonarr` over the host IP), and enable both Jellyfin libraries.

---

## 6. Current configuration notes

Observed on the running stack; useful when debugging drift.

- **Prowlarr:** applications Radarr and Sonarr with full sync; indexers `LimeTorrents`, `The Pirate Bay`, `YTS` enabled.
- **Radarr:** root `/data/media/movies`; qBittorrent `qbittorrent:8081`, category `radarr`; hardlinks on.
- **Sonarr:** root `/data/media/tv`; qBittorrent `qbittorrent:8081`, category `tv-sonarr`; hardlinks on.
- **qBittorrent:** WebUI `*:8081`, default save `/data/downloads/`, temp `/data/downloads/incomplete/`, categories `radarr` and `tv-sonarr` (no per-category save path, so both use the default). WebUI password is a PBKDF2 hash in `qBittorrent.conf`; no plaintext password is stored. Port forwarding is disabled.
- **Jellyfin:** server name `ld-jellyfin`; libraries Movies and Shows; remote access enabled; IPv6 disabled; HTTPS disabled; hardware acceleration `none` (see gotchas).
- **Seerr:** Jellyfin at `jellyfin:8096`; Radarr/Sonarr configured with the **host IP `192.168.7.10`**, not container names; only the **Movies** library is enabled in Seerr.
- **.env:** `PUID=1000`, `PGID=1000`, `TZ=Etc/UTC`, `JELLYFIN_PUBLISHED_URL=http://localhost:8096`, `SEERR_PORT=5055`, `SEERR_LOG_LEVEL=info`.
- **Jellyfin config is root-owned** because the container runs as root (the `user:` line is commented out). Do not blindly `chown -R 1000:1000` Jellyfin's config.

---

## 7. Daily operations

Run everything from `/home/pb/media-svr`.

```bash
docker compose ps
docker compose up -d
docker compose restart <service>
docker compose stop
docker compose start
docker compose down                # keeps bind-mounted data
docker compose logs -f --tail=200 <service>
docker compose config              # render anchors/env for inspection
```

Upgrades (images are on `latest`, so updates are manual):

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Check the release notes before pulling major Jellyfin/Seerr/arr upgrades.

---

## 8. Debugging

### 8.1 Triage checklist

```bash
cd /home/pb/media-svr

# Are all containers up and healthy?
docker compose ps
docker inspect --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' jellyfin seerr

# Did the compose file change or break?
docker compose config --quiet && echo OK

# Are the host ports listening?
ss -tlnp | grep -E ':(8096|9696|7878|8989|8081|5055)\b'

# Basic HTTP checks (302 from the arr apps is normal — they redirect to login)
curl -fsS http://localhost:8096/health
curl -fsS http://localhost:5055/api/v1/settings/public
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:7878
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8989
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:9696

# Disk space / inodes
df -h .
df -i .
```

### 8.2 Logs

| Service | Docker logs | On-disk logs |
|---|---|---|
| Jellyfin | `docker compose logs jellyfin` | `jellyfin/config/log/log_YYYYMMDD.log`, `FFmpeg.Transcode-*.log` |
| Radarr | `docker compose logs radarr` | `radarr/config/logs/radarr.txt`, `radarr.debug.txt` |
| Sonarr | `docker compose logs sonarr` | `sonarr/config/logs/sonarr.txt`, `sonarr.debug.txt` |
| Prowlarr | `docker compose logs prowlarr` | `prowlarr/config/logs/prowlarr.txt`, `prowlarr.debug.txt` |
| qBittorrent | `docker compose logs qbittorrent` | `qbittorrent/config/qBittorrent/logs/qbittorrent.log` |
| Seerr | `docker compose logs seerr` | `seerr/config/logs/seerr-YYYY-MM-DD.log` |

All at once:

```bash
docker compose logs -f --tail=100
```

Log rotation is commented out in `compose.yaml` (`x-common.logging`). If logs grow too large, uncomment that block and recreate containers.

### 8.3 API checks without leaking keys

API keys live in each app's `config.xml`. Extract them into shell variables; don't echo them.

```bash
# Radarr (API v3)
key=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' radarr/config/config.xml)
curl -s -H "X-Api-Key: $key" http://localhost:7878/api/v3/health | jq
curl -s -H "X-Api-Key: $key" 'http://localhost:7878/api/v3/queue?pageSize=50' \
  | jq '.records[] | {title, status, trackedDownloadStatus, errorMessage}'

# Sonarr (API v3)
key=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' sonarr/config/config.xml)
curl -s -H "X-Api-Key: $key" http://localhost:8989/api/v3/health | jq

# Prowlarr (API v1)
key=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' prowlarr/config/config.xml)
curl -s -H "X-Api-Key: $key" http://localhost:9696/api/v1/health | jq
curl -s -H "X-Api-Key: $key" http://localhost:9696/api/v1/indexer | jq '.[] | {name, enable}'
```

Jellyfin API keys are stored in its database, not in XML. Create one in **Dashboard → API Keys** if needed. Seerr's API key is `main.apiKey` in `seerr/config/settings.json`; treat it as a secret.

### 8.4 Connectivity and path checks

```bash
# Container DNS
docker compose exec sonarr getent hosts qbittorrent
docker compose exec radarr  getent hosts prowlarr

# qBittorrent reachable from the arr container
docker compose exec radarr curl -s -o /dev/null -w '%{http_code}\n' http://qbittorrent:8081

# Do all three see the same files?
docker compose exec qbittorrent ls -la /data/downloads
docker compose exec radarr      ls -la /data/downloads /data/media/movies
docker compose exec sonarr      ls -la /data/media/tv
docker compose exec jellyfin    ls -la /media/movies /media/tv

# Same device number => hardlinks are possible
docker compose exec radarr stat -c '%d %n' /data /data/downloads /data/media/movies
```

Verify an actual import/hardlink:

```bash
docker compose exec radarr stat -c '%i %h %n' \
  '/data/downloads/<release-file>' '/data/media/movies/<movie-folder>/<file>'
```

Same inode and link count > 1 means the import was hardlinked, not copied.

Permissions:

```bash
docker compose exec radarr id
docker compose exec radarr ls -ln /data/media/movies
ls -ln data data/media data/downloads
```

LinuxServer containers run as `abc` with `PUID:PGID` (1000:1000). Jellyfin runs as root. Media files should be readable by 1000:1000.

### 8.5 Symptom → checks

| Symptom | Check |
|---|---|
| Seerr request never appears in Radarr/Sonarr | Seerr's Radarr/Sonarr host + API key + root folder. Currently Seerr uses `192.168.7.10`; if the host IP changes, requests break. Prefer `radarr`/`sonarr`. |
| Added to Radarr/Sonarr but no search | Prowlarr indexers enabled and healthy; app sync in Prowlarr; quality profile; minimum availability; release already at quality cutoff. |
| Grabbed but nothing downloading | qBittorrent reachable at `qbittorrent:8081`; category `radarr`/`tv-sonarr`; torrent paused/errored; queue limits; disk full; tracker/port issues. |
| Downloaded but import fails | "No files found eligible for import" usually means path mismatch or permissions. Compare `/data/downloads` in qBittorrent vs Radarr/Sonarr. Confirm both see the same `/data`. Check category save path. Check that the release is not still unpacking. |
| Import copies instead of hardlinking | Cross-device paths, permissions, or qBittorrent still holding the file. Check device IDs and link counts above. |
| Imported but Jellyfin does not show it | Library path (`/media/movies`, `/media/tv`), trigger a library scan, check naming, check `:ro` mount visibility. |
| Playback buffers / CPU pegged | Transcoding. Hardware acceleration is currently `none`, and `/dev/dri` is not passed into the container. See 8.6. |
| Seerr cannot see TV requests/library | Only the Movies library is enabled in Seerr right now. Enable the Shows library in Seerr's Jellyfin settings. |
| Web UI unreachable | `docker compose ps`; port binding; host firewall; for qBittorrent check `WebUI\Address=*` and `Port=8081` in `qBittorrent.conf`. |
| App reports "database is locked" | Stop the app before copying/editing SQLite files. Never copy a live `.db` without its `-wal`/`-shm` siblings. |

### 8.6 Hardware transcoding (Jellyfin)

The host has `/dev/dri/renderD128`, but Jellyfin does not have it:

```bash
ls -la /dev/dri
docker inspect jellyfin --format '{{json .HostConfig.Devices}}'   # null
```

`encoding.xml` has `VaapiDevice=/dev/dri/renderD128` but `HardwareAccelerationType=none`. To enable VAAPI:

1. Add to the `jellyfin` service in `compose.yaml`:
   ```yaml
   devices:
     - /dev/dri:/dev/dri
   ```
2. `docker compose up -d jellyfin`
3. In Jellyfin **Dashboard → Playback → Transcoding**, select VAAPI and the render device, then save. Do not hand-edit `encoding.xml` while the container is running.
4. Test with a 4K HEVC file and watch `FFmpeg.Transcode-*.log` for `hevc_vaapi`/`h264_vaapi`.

If permission errors appear, check the host `render` group (GID 991 here) and add `group_add` for that GID. Jellyfin currently runs as root, which usually has access once the device is passed through.

### 8.7 qBittorrent password reset

The WebUI password is a PBKDF2 hash, not recoverable. If it is lost:

1. `docker compose stop qbittorrent`
2. Back up `qbittorrent/config/qBittorrent/qBittorrent.conf`
3. Remove the `WebUI\Password_PBKDF2=...` line
4. `docker compose start qbittorrent`
5. Check `docker compose logs qbittorrent` for a temporary password, then change it in the WebUI

Editing the file while the container is running will be overwritten on shutdown.

### 8.8 Seerr

- Settings: `seerr/config/settings.json` (contains API keys and session secrets — do not print or commit).
- Database: `seerr/config/db/db.sqlite3` (plus `-wal`/`-shm`).
- Logs: `seerr/config/logs/`.
- Current connections: Jellyfin `jellyfin:8096`; Radarr `192.168.7.10:7878`; Sonarr `192.168.7.10:8989`.
- If the host IP changes, update Radarr/Sonarr in Seerr. Container names are more stable inside this network.

---

## 9. Rules for agents working here

1. **Read this file first.** Then inspect `compose.yaml`, `.env.example`, and the relevant app config/logs.
2. **`compose.yaml` is the source of truth.** Shared defaults use YAML anchors (`x-common`, `x-host-gateway`, `x-linuxserver-env`, `x-tz-env`). Edit the anchor, not each service, for common settings. List-valued keys (`volumes`, `ports`, `command`) must stay per service.
3. **Validate after editing:** `docker compose config --quiet`.
4. **Do not hand-edit live app config** (`*/config/*.xml`, `*.conf`, `*.json`, SQLite DBs) while the container is running. Use the UI/API, or stop the container and back up the file first.
5. **Never delete** `data/` or `*/config/`; they contain the library and all app state. `jellyfin/cache/` and `data/downloads/incomplete/` are the only disposable areas.
6. **Do not print or commit secrets:** API keys in `*/config/config.xml`, `seerr/config/settings.json`, `.env`, qBittorrent hashes.
7. **Preserve service names and path mapping.** Prowlarr references `radarr`, `sonarr`, and `prowlarr` by name; Seerr references `jellyfin` by name. Renaming a service requires updating those references (and Seerr's Radarr/Sonarr connections, which currently use the host IP).
8. **Keep `./data` mounted at `/data`** in Radarr, Sonarr, and qBittorrent. Splitting or remapping these paths breaks imports and hardlinks.
9. **Keep Jellyfin's `/media` mount read-only** unless a specific plugin needs write access. Do not point Jellyfin at `data/downloads`.
10. **Keep ownership consistent** with `PUID`/`PGID` (1000:1000) for `data/` and LinuxServer config dirs. Jellyfin's own config is root-owned by design.
11. **Do not expose ports to the internet** or remove auth as a shortcut. There is no TLS/reverse proxy here.
12. **No git repository.** Before structural changes, make a config backup (section 10).
13. **Don't run `docker compose down -v`** or prune volumes; this stack uses bind mounts, but the command is still risky.
14. If you change ports or add a service, update this file and the relevant app connections.

---

## 10. Backup and restore

Stop the stack first so SQLite databases are consistent:

```bash
cd /home/pb/media-svr
docker compose stop

tar czf ~/media-svr-config-$(date +%F).tar.gz \
  --exclude='qbittorrent/config/qBittorrent/ipc-socket' \
  compose.yaml .env \
  jellyfin/config radarr/config sonarr/config prowlarr/config \
  qbittorrent/config seerr/config

docker compose start
```

- Exclude `jellyfin/cache/`, `data/downloads/`, and (optionally) `data/media/` from config backups. Media can be backed up separately if needed.
- Include the `-wal`/`-shm` files if copying databases manually; stopping the app is safer.
- Restore: extract over the directory, then `docker compose up -d`.

---

## 11. Known gotchas

1. **`JELLYFIN_PUBLISHED_URL` is `http://localhost:8096`.** LAN clients/autodiscovery will advertise localhost. Set it to the real LAN URL (or domain) in `.env`.
2. **Seerr points at `192.168.7.10` for Radarr/Sonarr.** This breaks if the host IP changes. Prefer `radarr`/`sonarr`.
3. **Seerr only has the Movies library enabled.** TV requests may not be recognized as available; enable Shows in Seerr.
4. **No hardware transcoding.** `/dev/dri` exists on the host but is not passed into Jellyfin, and VAAPI is not enabled. 4K HEVC/remux playback will use CPU.
5. **No VPN.** qBittorrent traffic egresses via the host's normal network. Port forwarding is disabled.
6. **Images use `latest`.** Upgrades are manual (`pull` + `up -d`) and can introduce breaking changes.
7. **Log rotation is off** (commented out in `compose.yaml`). Long-running verbose containers can fill disk.
8. **Jellyfin config is root-owned.** Ownership changes can break Jellyfin; leave its config alone unless you know why.
9. **Downloads may still be seeding.** Deleting files from `data/downloads` can break qBittorrent torrents and future hardlinked imports. Remove through the app or after checking qBittorrent.
10. **No reverse proxy/TLS.** Ports are exposed directly on the LAN; use Tailscale/VPN for remote access.
