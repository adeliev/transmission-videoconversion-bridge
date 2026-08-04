#!/bin/bash

# === watch_new_torrents.sh: перехват "богатого" имени торрента ===
#
# Transmission хранит добавленный магнет как /config/torrents/<hash>.magnet
# ТОЛЬКО пока не получены метаданные (список файлов) — как только они
# приходят от пиров (обычно за несколько секунд), файл заменяется на
# <hash>.torrent, а описательное имя из dn= безвозвратно теряется
# (замещается реальным именем файла из метаданных).
#
# Хука "добавлен торрент, но метаданных ещё нет" в Transmission не
# существует (script-torrent-added срабатывает уже ПОСЛЕ метаданных),
# поэтому здесь просто быстро опрашиваем папку и сохраняем dn=, пока
# файл ещё .magnet.

TORRENTS_DIR="/config/torrents"
STORE_DIR="/config/torrent_names"
SEEN_DB="/config/.torrent_names_seen"
LOGFILE="/logs/move.log"
POLL_INTERVAL=1

mkdir -p "$STORE_DIR"
touch "$SEEN_DB"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [watch_new_torrents] $1" >> "$LOGFILE"
}

log "🚀 Наблюдатель за новыми торрентами запущен."

while true; do
    for f in "$TORRENTS_DIR"/*.magnet; do
        [ -e "$f" ] || continue
        hash=$(basename "$f" .magnet)

        grep -Fxq "$hash" "$SEEN_DB" && continue

        # Уже сохранено раньше (например, разовый backfill) - не трогаем
        if [ -f "$STORE_DIR/$hash.txt" ]; then
            echo "$hash" >> "$SEEN_DB"
            continue
        fi
        echo "$hash" >> "$SEEN_DB"

        dn=$(python3 -c "
import sys
from urllib.parse import urlparse, parse_qs
try:
    content = open(sys.argv[1], encoding='utf-8').read().strip()
    qs = parse_qs(urlparse(content).query)
    print(qs.get('dn', [''])[0])
except Exception:
    pass
" "$f" 2>>"$LOGFILE")

        if [ -n "$dn" ]; then
            printf '%s' "$dn" > "$STORE_DIR/$hash.txt"
            log "💾 Захвачено имя для $hash: $dn"
        fi
    done
    sleep "$POLL_INTERVAL"
done
