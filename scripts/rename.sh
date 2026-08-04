#!/bin/bash

# === rename.sh: Умное переименование и организация (Только MP4) ===

MOV_MP4="/media/Downloads/Movies/MP4"
TV_MP4="/media/Downloads/TV-Shows/MP4"
LOGFILE="/logs/rename.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"

# Не даём двум экземплярам rename.sh работать одновременно - см. tag.sh
exec 200>"/config/.rename.sh.lock"
if ! flock -n 200; then
    log "⏭️  Уже выполняется другой rename.sh, пропуск"
    exit 0
fi

rename_movies() {
    local dir="$1"

    log "🎬 Обработка фильмов в $dir..."
    find "$dir" -maxdepth 1 -type f -iname "*.mp4" | while read -r file; do
        local filename=$(basename "$file")
        local base="${filename%.*}"
        local ext="${filename##*.}"
        local sidecar="$file.torrentinfo.json"

        local new_base=""

        # Приоритет - имя из торрента (item 4), если оно есть и не сериал
        # Год в имя файла не идёт - только в теги/поиск (см. tmdb_tagger.py)
        if [ -f "$sidecar" ]; then
            local is_tv=$(/scripts/read_torrent_info.py "$sidecar" is_tv)
            if [ "$is_tv" != "True" ]; then
                new_base=$(/scripts/read_torrent_info.py "$sidecar" display_title)
            fi
        fi

        # Фолбэк - грубая очистка имени файла, как раньше
        if [ -z "$new_base" ]; then
            new_base=$(/scripts/clean_name.py "$base")
        fi

        if [ "$base" != "$new_base" ] && [ -n "$new_base" ]; then
            local new_file="$dir/$new_base.$ext"
            if [ -f "$new_file" ]; then continue; fi
            mv "$file" "$new_file"
            [ -f "$sidecar" ] && mv "$sidecar" "$new_file.torrentinfo.json"
            log "🏷️  Переименовано: '$filename' -> '$new_base.$ext'"
        fi
    done
}

rename_tv_shows() {
    local dir="$1"

    log "📺 Обработка сериалов в $dir..."
    # convert.sh кидает все в корень TV_MP4, поэтому ищем в maxdepth 1.
    
    find "$dir" -maxdepth 1 -type f -iname "*.mp4" | while read -r file; do
        local filename=$(basename "$file")
        local sidecar="$file.torrentinfo.json"

        # Получаем инфо: Name|Season|Episode
        # Номер серии всегда берём из имени файла - в имени торрента есть
        # только диапазон серий пака, а не номер конкретного файла.
        local info=$(/scripts/tv_info.py "$filename")

        if [ $? -ne 0 ] || [ -z "$info" ]; then
            # Если не удалось распарсить, пропускаем (возможно это не сериал или странное имя)
            # log "⚠️  Не удалось распарсить сериал: $filename"
            continue
        fi

        # Разбиваем строку по разделителю |
        IFS='|' read -r show_name season_num episode_num <<< "$info"

        # Приоритет - название сериала из торрента (item 4), если есть
        if [ -f "$sidecar" ]; then
            local rich_show=$(/scripts/read_torrent_info.py "$sidecar" display_title)
            [ -n "$rich_show" ] && show_name="$rich_show"
        fi

        # Форматируем номера (s01e01)
        # Force decimal base with 10# to avoid octal interpretation of 08, 09
        local s_pad=$(printf "%02d" $((10#$season_num)))
        local e_pad=$(printf "%02d" $((10#$episode_num)))

        # Структура: Show Name/Season X/Show Name - sXXeYY.mp4
        # Season X (без ведущего нуля для папки, как обычно принято)
        # Русские сериалы (название кириллицей) - папка "Сезон N"
        local season_folder="Season $season_num"
        if /scripts/is_cyrillic.py "$show_name"; then
            season_folder="Сезон $season_num"
        fi
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
        [ -f "$sidecar" ] && mv "$sidecar" "$target_path.torrentinfo.json"
        log "📦 Организовано: $filename -> $target_dir/$final_name"
    done
}

# 1. Фильмы
rename_movies "$MOV_MP4"

# 2. Сериалы
rename_tv_shows "$TV_MP4"