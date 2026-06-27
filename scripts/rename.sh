#!/bin/bash

# === rename.sh: Умное переименование и организация (Только MP4) ===

MOV_MP4="/movies/MP4"
TV_MP4="/downloads_host/TV-Shows/MP4"
LOGFILE="/logs/rename.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"

rename_movies() {
    local dir="$1"
    
    log "🎬 Обработка фильмов в $dir..."
    find "$dir" -maxdepth 1 -type f -iname "*.mp4" | while read -r file; do
        local filename=$(basename "$file")
        local base="${filename%.*}"
        local ext="${filename##*.}"

        local year=$(echo "$base" | grep -oE '(19|20)[0-9]{2}' | tail -1)
        local new_base=$(/scripts/clean_name.py "$base")

        if [ "$base" != "$new_base" ] && [ -n "$new_base" ]; then
            local display_name="$new_base"
            [ -n "$year" ] && display_name="$new_base ($year)"
            local new_file="$dir/$display_name.$ext"
            if [ -f "$new_file" ]; then continue; fi
            mv "$file" "$new_file"
            log "🏷️  Переименовано: '$filename' -> '$display_name.$ext'"
        fi
    done
}

rename_tv_shows() {
    local dir="$1"

    log "📺 Обработка сериалов в $dir..."
    # convert.sh кидает все в корень TV_MP4, поэтому ищем в maxdepth 1.
    
    find "$dir" -maxdepth 1 -type f -iname "*.mp4" | while read -r file; do
        local filename=$(basename "$file")
        
        # Получаем инфо: Name|Season|Episode
        local info=$(/scripts/tv_info.py "$filename")
        
        if [ $? -ne 0 ] || [ -z "$info" ]; then
            # Если не удалось распарсить, пропускаем (возможно это не сериал или странное имя)
            # log "⚠️  Не удалось распарсить сериал: $filename"
            continue
        fi

        # Разбиваем строку по разделителю |
        IFS='|' read -r show_name season_num episode_num <<< "$info"
        
        # Форматируем номера (s01e01)
        # Force decimal base with 10# to avoid octal interpretation of 08, 09
        local s_pad=$(printf "%02d" $((10#$season_num)))
        local e_pad=$(printf "%02d" $((10#$episode_num)))
        
        # Структура: Show Name/Season X/Show Name - sXXeYY.mp4
        # Season X (без ведущего нуля для папки, как обычно принято)
        local season_folder="Season $season_num" 
        local final_name="$show_name - s${s_pad}e${e_pad}.mp4"
        
        local target_dir="$dir/$show_name/$season_folder"
        local target_path="$target_dir/$final_name"
        
        if [ "$file" == "$target_path" ]; then
            continue
        fi

        mkdir -p "$target_dir"
        
        if [ -f "$target_path" ]; then
            log "⚠️  Файл уже существует: $target_path"
            # Можно удалить исходник (раскомментировать, если нужно)
            # rm "$file"
            continue
        fi
        
        mv "$file" "$target_path"
        log "📦 Организовано: $filename -> $target_dir/$final_name"
    done
}

# 1. Фильмы
rename_movies "$MOV_MP4"

# 2. Сериалы
rename_tv_shows "$TV_MP4"