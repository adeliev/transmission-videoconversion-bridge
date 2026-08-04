# Transmission Video Conversion Bridge

Automated download, conversion, and tagging pipeline for movies and TV shows, built on the Transmission BitTorrent client and Docker.

**[Русская версия](README.ru.md)** | **English**

## Description

This project is a Docker container running Transmission, extended with a chain of scripts that turn a finished torrent into a properly named, tagged, library-ready file:

- Automatic pickup of completed downloads (movies and TV shows, single episodes or full season packs)
- Video conversion to MP4/H.264, with audio/subtitle tracks filtered down to the languages you care about
- Filename and folder naming derived from the actual torrent release name (rutracker-style), not the often-cryptic source filename
- Full metadata tagging via the TMDB API — iTunes-style tags (title, artist, cast/crew, description, poster, content rating) for both movies and TV episodes
- Automatic routing into the right library folder, including Cyrillic- vs Latin-title detection for TV shows
- Watch-folder monitoring for automatic `.torrent` addition

## Features

- **Fully Automatic Pipeline**: a 30-minute loop runs convert → rename → tag → publish with no manual steps
- **Movies and TV Shows**: season/episode detection from the torrent's own release name, including Russian multi-season-pack conventions (`Show-N (NN сер.)`) and packs with no per-file episode markers at all
- **Smart Renaming**: derives clean names and folder structure from the parsed torrent name (title, season, year, country) instead of the raw release filename
- **Audio/Subtitle Filtering**: keeps only the languages you want (default: Russian/English/Slovak/Czech), prefers full subtitles over forced-only tracks
- **TMDB Integration**: Russian-priority metadata with automatic fallback to the original title/no-year search when a strict query returns nothing
- **iTunes-Parity Tagging**: content rating and full cast/crew/studio info (`iTunEXTC`/`iTunMOVI`), matching what Subler would produce
- **Safe Concurrency**: file locks around every stage so a manual run never collides with the scheduled cycle
- **Single Bind Mount for Staging + Downloads + Library**: avoids slow copy-then-delete moves inside the container — everything under one mount so `mv` is an instant rename

## Project Structure

```
transmission-videoconversion-bridge/
├── Dockerfile                    # Docker image with dependencies (ffmpeg, python3, mutagen, ...)
├── docker-compose.yml            # Docker Compose configuration
├── docker-compose.example.yml    # Template to copy and adapt
├── scripts/
│   ├── move.sh                   # torrent-done hook: moves finished files into staging
│   ├── watch_new_torrents.sh     # background poller, captures the rich torrent name before
│   │                              # Transmission overwrites it with real file metadata
│   ├── convert.sh                # video conversion to MP4/H.264 via ffmpeg
│   ├── get_ffmpeg_map.py         # decides which audio/subtitle streams to keep, by language
│   ├── rename.sh                 # organizes staged files into Show/Season or clean movie names
│   ├── parse_torrent_name.py     # parses rutracker-style release names into structured fields
│   ├── plan_tv_episode_names.py  # infers episode numbers for packs with no sXXeYY markers
│   ├── tv_info.py                # season/episode detection helpers, incl. Russian pack conventions
│   ├── read_torrent_info.py      # reads fields back out of the .torrentinfo.json sidecar
│   ├── is_cyrillic.py            # Cyrillic-vs-Latin title check, drives folder naming/routing
│   ├── clean_name.py             # fallback filename cleanup when no torrent-name parse is available
│   ├── tag.sh / tmdb_tagger.py    # TMDB lookup + full metadata/poster/cast tagging
│   ├── publish.sh                # moves fully-tagged files from staging into the library
│   └── monitor.sh                # the scheduling loop: convert → rename → tag → publish, every 30 min
├── init-scripts/                 # container auto-start scripts
├── config/                       # Transmission configuration (excluded from git)
├── logs/                         # per-stage log files (excluded from git)
└── watch/                        # torrent watch folder (excluded from git)
```

## Installation

### Prerequisites

- Docker
- Docker Compose
- A media library folder on the host (used for both staging and the final library — see note below)

### Quick Start

1. Clone the repository:
```bash
git clone https://github.com/adeliev/transmission-videoconversion-bridge.git
cd transmission-videoconversion-bridge
```

2. Copy the example configuration:
```bash
cp docker-compose.example.yml docker-compose.yml
```

3. Edit `docker-compose.yml`:
   - Change `USER` and `PASS` for the web interface
   - Set `/path/to/your/media` to a real path on your host (see **Mounted Volumes** below — this one mount doubles as the download destination, the processing staging area, and the final library)
   - Set the correct timezone
   - If you want inbound peer connections to work well, forward the peer port (`51414` by default) on your router to this host, TCP+UDP, matching the port on both sides of the `ports:` mapping

4. Create necessary folders:
```bash
mkdir -p config watch logs init-scripts
```

5. Start the container:
```bash
docker compose up -d
```

6. Open the Transmission web interface:
```
http://localhost:9091
```

## Configuration

### Environment Variables

- `PUID` / `PGID` - User and group ID for proper file permissions
- `TZ` - Timezone (e.g., Europe/London, America/New_York)
- `USER` / `PASS` - Web interface credentials
- `TRANSMISSION_SCRIPT_TORRENT_DONE_ENABLED` - Enable post-completion script
- `TRANSMISSION_SCRIPT_TORRENT_DONE_FILENAME` - Path to processing script

### Mounted Volumes

- `./config` - Transmission configuration
- `./scripts` - Processing scripts
- `./logs` - Log files
- `./watch` - Automatic torrent addition folder
- `/path/to/your/media:/media` - **single mount** covering:
  - Transmission's own `incomplete`/`complete` download folders (`<media>/Downloads/incomplete`, `.../complete`)
  - The processing staging area (`<media>/Downloads/Movies/...`, `<media>/Downloads/TV-Shows/...`)
  - The final library (`<media>/New`, `<media>/Series`, `<media>/TVShows`)

  These must all live on the **same** bind mount. If any of them is a separate mount, every `mv` between stages becomes a copy-then-delete inside the container even though the underlying host paths may be on the same physical disk — Docker bind mounts are separate mount namespaces regardless of the host filesystem underneath.

### Ports

- `9091` - Transmission web interface
- `51414` - BitTorrent peer port (TCP/UDP)

The host port and the container's internal `peer-port` (in `config/settings.json`) **must match** — BitTorrent announces its own listening port to trackers/DHT/peers, so if the host-side port mapping remaps to a different container port, incoming connections silently never arrive, even if your router forwarding is otherwise correct. Check reachability any time with:
```bash
docker exec transmission-downloader transmission-remote -n <user>:<pass> -pt
```

## How It Works

The whole pipeline is driven by `monitor.sh`, which runs `convert.sh → rename.sh → tag.sh → publish.sh` in a loop every 30 minutes (plus an independent background poller, `watch_new_torrents.sh`).

1. **Download**: Transmission downloads to `<media>/Downloads/incomplete`, then `.../complete`.
2. **Capture the release name**: as soon as a torrent is added, `watch_new_torrents.sh` saves its full rutracker-style name (title, season/episode range, year, country, genre) from the magnet — this has to happen immediately, because Transmission overwrites the torrent's display name with real file metadata once it fetches it.
3. **Move**: on completion, `move.sh` (the `torrent-done` hook) parses that saved name via `parse_torrent_name.py`, decides movie vs. TV show **once per torrent** (not per file), and moves the video file(s) into staging, attaching a `.torrentinfo.json` sidecar with the parsed fields.
4. **Convert**: `convert.sh` transcodes to MP4/H.264 as needed, using `get_ffmpeg_map.py` to keep only the audio/subtitle languages you want.
5. **Rename**: `rename.sh` organizes staged files using the parsed torrent name — `Show Name/Season N/Show Name - sNNeNN.mp4` for TV (or `Сезон N` if the show's title is Cyrillic), clean `Title (Year).mp4` for movies. For packs with no recognizable per-file episode markers, `plan_tv_episode_names.py` infers episode numbers from whichever filename token actually varies across the pack.
6. **Tag**: `tag.sh`/`tmdb_tagger.py` looks the title up on TMDB (Russian-priority, falling back to an unrestricted search if the strict query finds nothing), embeds full iTunes-style tags plus poster and cast/crew, and only then removes the `.torrentinfo.json` sidecar — a file that fails tagging keeps its sidecar so a later run can be identified as still-incomplete.
7. **Publish**: `publish.sh` moves fully-tagged movies straight to `<media>/New`, and TV seasons to `<media>/Series` (Cyrillic show names) or `<media>/TVShows` (Latin), publishing a season only once every file staged for it is fully tagged.

## Troubleshooting

- **A file seems stuck / never gets published**: check `logs/tag.log` for that file. `tag.sh` marks every file it processes as "attempted" the moment it runs, even if the TMDB lookup fails (so a genuinely-unmatched title doesn't get retried forever) — that means a *transient* failure (a momentary DNS/network hiccup, or a wrong title on the torrent) can also get permanently skipped. Fix: confirm the real problem is resolved, remove that file's exact path from `config/tagged_files.txt`, then re-run `tag.sh` and `publish.sh` manually.
- **Slow, unstable download speed despite visible peers/seeds**: check `transmission-remote -pt` (port test). If it reports the port closed, incoming peer connections aren't reaching you at all — you're limited to peers who can dial out to you, which is a small fraction of any swarm. See the **Ports** section above for the host/container port-matching requirement, plus router-side forwarding.

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

Created for automated media file processing
