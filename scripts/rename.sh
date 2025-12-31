#!/bin/bash

# === rename.sh: Умное переименование (Только MP4) ===

DIR_MP4="/movies/MP4"
LOGFILE="/logs/rename.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rename_in_dir() {
    local dir="$1"
    local ext_pattern="$2"

    find "$dir" -maxdepth 1 -type f -iname "$ext_pattern" | while read -r file; do
        local filename=$(basename "$file")
        local base="${filename%.*}"
        local ext="${filename##*.}"

        # Используем общий скрипт очистки
        local new_base=$(/scripts/clean_name.py "$base")

        # Если имя изменилось (и оно не пустое)
        if [ "$base" != "$new_base" ] && [ -n "$new_base" ]; then
            local new_file="$dir/$new_base.$ext"
            
            # Проверяем, не занято ли новое имя
            if [ -f "$new_file" ]; then
                # Можно добавить логику: если занято, но файлы идентичны - удалить старый
                continue
            fi

            mv "$file" "$new_file"
            log "🏷️  Переименовано: '$filename' -> '$new_base.$ext'"
        fi
    done
}

# Переименовываем ТОЛЬКО MP4
rename_in_dir "$DIR_MP4" "*.mp4"