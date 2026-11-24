# media-svr

One Compose project (`name: media-svr`) holding the whole media stack: Jellyfin as the
front end, Prowlarr/Radarr/Sonarr as the *arr trio, Seerr for requests, and Open WebUI
bolted on the side.

The stack is *run* from the single `compose.yaml` at the root of this directory. Per-app
subdirectories exist to hold the upstream templates, notes and per-app assets, not to be
deployed separately.

## Layout

```text
docker/media-svr/
├── compose.yaml            # the whole stack; the only file `docker compose` reads
├── .env                    # local values (PUID, paths, secret) - gitignored
├── .env.example            # documented, committable copy of .env
├── README.md
├── jellyfin/
│   ├── compose.yaml        # upstream template for this app, unmodified where possible
│   └── README.md           # what we changed, ports, volumes, gotchas
├── prowlarr/
│   ├── compose.yaml
│   └── README.md
├── radarr/
│   ├── compose.yaml
│   └── README.md
├── sonarr/
│   ├── compose.yaml
│   └── README.md
├── seerr/
│   ├── compose.yaml
│   └── README.md
└── open-webui/
    ├── compose.yaml
    └── README.md
```

### Why not one compose file per app service?

Because YAML anchors are file-scoped. The `x-common`, `x-linuxserver-env`, `x-tz-env`
and `x-host-gateway` blocks in the root file would have to be copy-pasted into every
sub-file, and they would drift. Compose's `include:` directive (Compose v2.20+) can
stitch per-app files together, but it still does not share anchors across files, so you
pay the duplication either way.

Keep exactly one runnable file. If you ever do split, split by *stack*, not by *app*.

### Why keep per-app directories at all?

- The upstream examples (jellyfin docs, linuxserver.io, seerr) are the source of truth for
  image tags, ports and env keys. Keeping an untouched copy next to the merged service
  makes the next `docker compose pull`-and-compare review trivial.
- Each app gets a place for non-YAML assets: fonts for Jellyfin subtitle burn-in,
  plugin bundles, config snippets, RSS proxy lists.
- The per-app `README.md` is where you record cluster- or host-specific decisions
  ("Jellyfin runs as root here because the NFS export squashes uid", and so on).

State that lives next to the code:

- `jellyfin/fonts/` — bind-mounted to `/usr/local/share/fonts/custom`
- `prowlarr/definitions/` — optional, for custom indexer definitions

Everything else (config, media, downloads) lives outside the repo, see below.

## Paths: the one structural decision that matters

The current file is full of `/path/to/...` placeholders. Resolve them through `.env`
rather than by editing `compose.yaml` per host:

```dotenv
# .env
PUID=1000
PGID=1000
TZ=Etc/UTC

APPDATA_ROOT=/srv/media-svr/appdata
MEDIA_ROOT=/srv/media-svr/data

WEBUI_SECRET_KEY=change-me
```

```yaml
# compose.yaml
  PUID: ${PUID}
  PGID: ${PGID}
```

### Keep downloads and media under one parent

Radarr and Sonarr need to hardlink (or at least atomically move) from the download client
into the library. That only works when both paths are inside the same filesystem, and it
only works reliably when every container sees them at the *same* paths. So use a single
`${MEDIA_ROOT}` with subdirectories, mounted identically everywhere:

```text
/srv/media-svr/
├── appdata/
│   ├── jellyfin/config
│   ├── jellyfin/cache
│   ├── prowlarr/config
│   ├── radarr/config
│   ├── sonarr/config
│   ├── seerr/config
│   └── open-webui/            # named volume today; a bind mount is easier to back up
└── data/
    ├── media/
    │   ├── movies/
    │   └── tv/
    ├── downloads/
    │   ├── incomplete/
    │   └── complete/
    └── torrents/
```

and in Compose:

```yaml
    volumes:
      - ${MEDIA_ROOT}:/data
```

with Radarr's root folder pointing at `/data/media/movies` and its download client at
`/data/downloads`. The upstream templates mount `/movies` and `/downloads` as two
separate paths, which quietly breaks hardlinks — that is the change worth making on
import.

### Config directories

LinuxServer images (`prowlarr`, `radarr`, `sonarr`) all expect `/config`. Point them at
`${APPDATA_ROOT}/<app>/config`. Don't put appdata inside the repo: it is chmod'd, full of
SQLite files, and would end up in `git status` the moment something writes a lock file.

## Network

The default project network is enough — Compose already isolates `media-svr` and gives
every service DNS by service name (`http://sonarr:8989`). Only add an explicit `networks:`
block when something outside the project needs to reach a container, and then prefer a
single named `external` network over `network_mode: host`.

Published ports, for reference (all currently bound on all interfaces):

| Port | Service | Notes |
| ---- | ------- | ----- |
| 8096/tcp | Jellyfin | web UI |
| 7359/udp | Jellyfin | client autodiscovery |
| 9696 | Prowlarr | |
| 7878 | Radarr | |
| 8989 | Sonarr | |
| 5055 | Seerr | |
| 3000 | Open WebUI | container port 8080 |

`JELLYFIN_PublishedServerUrl` needs the host's real address or hostname for autodiscovery
to work — set it via `.env`, not as `http://example.com`.

## Secrets

- `WEBUI_SECRET_KEY` in Open WebUI must be a real random value
  (`openssl rand -hex 32`) and must not be committed. Keep it in `.env`.
- Nothing else in this stack holds a credential in Compose; API keys for Prowlarr ->
  Radarr/Sonarr are generated on first run and live in `appdata/`.

## Git hygiene

Add to the repo `.gitignore` (or a local one here):

```gitignore
.env
appdata/
data/
```

Commit `.env.example` instead, and keep `compose.yaml` free of host-specific paths.

## Working with the stack

```sh
cp .env.example .env      # then fill it in
docker compose config     # verify variable interpolation before starting
docker compose up -d
docker compose logs -f seerr
```

Bootstrap order on a fresh host:

1. `prowlarr`, `radarr`, `sonarr` — set root folders to `/data/media/{movies,tv}`, add the
   download client with path `/data/downloads`.
2. Prowlarr indexers, then push them to Radarr/Sonarr from Prowlarr's *Settings > Apps*.
3. `jellyfin` — add `/media` and `/media2` libraries only after the paths exist.
4. `seerr` — point at Jellyfin and the *arr APIs.
5. `open-webui` — unrelated to the rest; see the note below.

## Loose ends worth fixing

Called out because they are easy to miss when copying the templates in:

- **Open WebUI does not belong in this project.** It is an LLM front end with no coupling
  to the media stack. Move it to `docker/open-webui/compose.yaml` as its own project.
- **`latest` and `main` tags everywhere.** No rollback story. Once the stack is stable,
  pin versions and let Renovate bump them, matching what the rest of this repo does.
- **No log limits.** The commented-out `logging:` block in `x-common` is the right idea;
  `json-file` with `max-size: 10m` and `max-file: "3"` costs nothing and prevents a
  runaway container from filling the disk.
- **No healthchecks outside Seerr.** The *arr trio can be healthchecked on
  `/<app>/ping` if you want `depends_on` to mean anything.
- **Jellyfin runs as root.** Add `user: "${PUID}:${PGID}"` once you know the media files
  are owned consistently, and make sure the transcode/cache path is writable by that uid.
