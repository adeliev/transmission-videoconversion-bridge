# Transmission Video Conversion Bridge

Automated video file download and processing system based on Transmission BitTorrent client and Docker.

**[Русская версия](README.ru.md)** | **English**

## Description

This project is a Docker container with Transmission BitTorrent client extended with a set of scripts for automatic processing of downloaded files:

- Automatic moving of completed downloads
- Video conversion to optimal formats
- Filename cleaning and normalization
- Automatic tagging via TMDB API
- Watch folder monitoring for automatic torrent addition

## Features

- **Automatic Processing**: Scripts run automatically after download completion
- **Video Conversion**: Automatic conversion using FFmpeg
- **Smart Renaming**: Cleans filenames from technical tags and artifacts
- **TMDB Integration**: Automatic movie metadata retrieval
- **Watch Folder**: Automatic monitoring for new torrents

## Project Structure

```
transmission-videoconversion-bridge/
├── Dockerfile                 # Docker image with dependencies
├── docker-compose.yml         # Docker Compose configuration
├── scripts/                   # Processing scripts
│   ├── move.sh               # Move completed files
│   ├── convert.sh            # Video conversion
│   ├── monitor.sh            # Watch folder monitoring
│   ├── rename.sh             # File renaming
│   ├── tag.sh                # Metadata tagging
│   ├── clean_name.py         # Filename cleaning
│   └── tmdb_tagger.py        # TMDB API integration
├── init-scripts/             # Auto-start scripts
├── config/                   # Transmission config (excluded from git)
├── logs/                     # Log files (excluded from git)
├── downloads/                # Temporary downloads (excluded from git)
└── watch/                    # Torrent watch folder (excluded from git)
```

## Installation

### Prerequisites

- Docker
- Docker Compose

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
   - Change `USER` and `PASS` for web interface
   - Configure paths to folders on your system
   - Set the correct timezone

4. Create necessary folders:
```bash
mkdir -p config downloads watch logs init-scripts
```

5. Start the container:
```bash
docker-compose up -d
```

6. Open Transmission web interface:
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
- `./downloads` - Temporary download folder
- `./watch` - Automatic torrent addition folder

## Scripts

### move.sh
Main script called after download completion. Determines file type and moves it to the appropriate folder.

### convert.sh
Converts video files to optimal format using FFmpeg.

### monitor.sh
Monitors the watch folder and automatically adds new .torrent files to Transmission.

### clean_name.py
Python script for cleaning filenames from technical tags and formatting.

### tmdb_tagger.py
Retrieves movie metadata from TMDB and adds tags to files.

## Ports

- `9091` - Transmission web interface
- `51414` - BitTorrent (TCP/UDP)

## Logs

All logs are saved to `./logs/` folder:
- File moving logs
- Conversion logs
- Monitoring logs

## How It Works

1. **Download**: Transmission downloads torrent files to the `./downloads` folder
2. **Post-Processing**: When download completes, `move.sh` is triggered
3. **Analysis**: Script determines if the file is a video and analyzes its properties
4. **Conversion**: If needed, video is converted to optimal format using `convert.sh`
5. **Tagging**: Metadata is retrieved from TMDB and added to the file
6. **Moving**: File is moved to the final destination based on type (movies/downloads)
7. **Watch Folder**: `monitor.sh` continuously watches for new .torrent files

## Use Cases

- **Home Media Server**: Automatically download and organize movies
- **Media Collection Management**: Clean naming and proper metadata
- **Format Standardization**: Convert all videos to a consistent format
- **Automated Workflow**: Minimal manual intervention required

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

Created for automated media file processing
