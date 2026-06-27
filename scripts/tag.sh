#!/bin/bash

# === tag.sh: Добавление метаданных через TMDB ===

DIR_MP4="/movies/MP4"
TAGGED_DB="/config/tagged_files.txt"
LOGFILE="/logs/tag.log"

# Создаем БД обработанных файлов, если нет
touch "$TAGGED_DB"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"

log "🚀 Запуск tag.sh"

find "$DIR_MP4" -maxdepth 1 -type f -iname "*.mp4" | while read -r file; do
    filename=$(basename "$file")
    
    # Проверяем, был ли файл уже обработан
    if grep -Fxq "$filename" "$TAGGED_DB"; then
        # log "⏭️  Пропуск (уже обработан): $filename"
        continue
    fi

    log "🔎 Обработка: $filename"

    # Запускаем Python-теггер
    python3 /scripts/tmdb_tagger.py "$file"
    
    # Если скрипт отработал (не упал), считаем попытку совершенной
    # (даже если фильм не найден, чтобы не долбить API вечно)
    echo "$filename" >> "$TAGGED_DB"
    
done
