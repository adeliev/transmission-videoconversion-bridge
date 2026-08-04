#!/bin/bash

# === monitor.sh: Планировщик задач ===
# Запускает конвертацию и переименование каждые 30 минут

LOGFILE="/logs/monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"

log "🚀 Монитор запущен."

while true; do
    log "⏰ Запуск плановых задач..."

    # 1. Запуск конвертации
    /scripts/convert.sh

    # 2. Запуск переименования
    /scripts/rename.sh

    # 3. Запуск тегирования (TMDB)
    /scripts/tag.sh

    # 4. Перенос готового в библиотеку
    /scripts/publish.sh

    log "💤 Ожидание 30 минут..."
    sleep 1800
done
