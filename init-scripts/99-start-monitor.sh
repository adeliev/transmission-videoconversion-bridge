#!/bin/bash
echo "🚀 [Custom Init] Starting Monitor Script in background..."
/scripts/monitor.sh &
echo "🚀 [Custom Init] Starting Torrent-Name Watcher in background..."
/scripts/watch_new_torrents.sh &
