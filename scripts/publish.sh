#!/bin/bash

# === publish.sh: Перенос готовых (сконвертированных, переименованных,
#     оттегированных) файлов из стейджинга в постоянную библиотеку ===
#
# Фильмы -> /media/New
# Сериалы: кириллица в названии -> /media/Series, иначе -> /media/TVShows
#          (если сезоны шоу уже есть в библиотеке - просто дописываем)

DIR_MOVIES="/media/Downloads/Movies/MP4"
DIR_TV="/media/Downloads/TV-Shows/MP4"
DEST_MOVIES="/media/New"
DEST_SERIES="/media/Series"
DEST_TVSHOWS="/media/TVShows"
TAGGED_DB="/config/tagged_files.txt"
LOGFILE="/logs/publish.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"

# Не даём двум экземплярам publish.sh работать одновременно - см. tag.sh
exec 200>"/config/.publish.sh.lock"
if ! flock -n 200; then
    log "⏭️  Уже выполняется другой publish.sh, пропуск"
    exit 0
fi

# Файл прошёл тегирование успешно (а не просто "попытку") тогда и только
# тогда, когда он есть в TAGGED_DB И у него больше нет .torrentinfo.json
# (tmdb_tagger.py удаляет сайдкар именно при успехе - см. item 4)
is_fully_tagged() {
    local file="$1"
    [ -f "$file.torrentinfo.json" ] && return 1
    grep -Fxq "$file" "$TAGGED_DB" 2>/dev/null
}

publish_movies() {
    mkdir -p "$DEST_MOVIES"
    find "$DIR_MOVIES" -maxdepth 1 -type f -iname "*.mp4" | while read -r file; do
        is_fully_tagged "$file" || continue

        local filename=$(basename "$file")
        local target="$DEST_MOVIES/$filename"

        if [ -f "$target" ]; then
            log "⚠️  Уже есть в библиотеке, пропуск: $filename"
            continue
        fi

        mv "$file" "$target"
        log "📚 Фильм опубликован: $filename"
    done
}

publish_tv_shows() {
    find "$DIR_TV" -mindepth 1 -maxdepth 1 -type d | while read -r show_dir; do
        local show_name=$(basename "$show_dir")

        find "$show_dir" -mindepth 1 -maxdepth 1 -type d | while read -r season_dir; do
            local season_name=$(basename "$season_dir")

            # Публикуем сезон только когда ВСЕ эпизоды в нём готовы -
            # чтобы в библиотеке не оказывался наполовину оттегированный сезон
            local all_ready=1
            while read -r ep; do
                is_fully_tagged "$ep" || { all_ready=0; break; }
            done < <(find "$season_dir" -maxdepth 1 -type f -iname "*.mp4")

            if [ "$all_ready" -ne 1 ]; then
                continue
            fi

            local dest_root="$DEST_TVSHOWS"
            if /scripts/is_cyrillic.py "$show_name"; then
                dest_root="$DEST_SERIES"
            fi

            local dest_season_dir="$dest_root/$show_name/$season_name"
            mkdir -p "$dest_season_dir"

            find "$season_dir" -maxdepth 1 -type f -iname "*.mp4" | while read -r ep; do
                local epname=$(basename "$ep")
                local target="$dest_season_dir/$epname"

                if [ -f "$target" ]; then
                    log "⚠️  Уже есть в библиотеке, пропуск: $show_name/$season_name/$epname"
                    continue
                fi

                mv "$ep" "$target"
                log "📚 Серия опубликована: $show_name/$season_name/$epname"
            done

            # Чистим опустевшие папки в стейджинге. rmdir отказывается
            # удалять "непустую" папку из-за .DS_Store (macOS Finder
            # создаёт его заново при любом просмотре папки) - поэтому
            # сначала убираем такой мусор явно.
            find "$season_dir" -maxdepth 1 -name ".DS_Store" -delete 2>/dev/null
            rmdir "$season_dir" 2>/dev/null
            find "$show_dir" -maxdepth 1 -name ".DS_Store" -delete 2>/dev/null
            rmdir "$show_dir" 2>/dev/null
        done
    done
}

publish_movies
publish_tv_shows
