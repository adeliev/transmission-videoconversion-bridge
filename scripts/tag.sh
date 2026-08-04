#!/bin/bash

# === tag.sh: Добавление метаданных через TMDB ===

DIR_MOVIES="/media/Downloads/Movies/MP4"
DIR_TV="/media/Downloads/TV-Shows/MP4"
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

# Не даём двум экземплярам tag.sh работать одновременно (например, ручной
# запуск наложился на плановый цикл monitor.sh) - иначе они гоняются за
# одним и тем же временным файлом (<file>.temp.mp4) и портят друг другу
# результат (проверено на реальных файлах - гонка приводила к "лишней"
# отвязанной обложке и обрывам ffmpeg с ошибкой чтения/записи).
exec 200>"/config/.tag.sh.lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ⏭️  Уже выполняется другой tag.sh, пропуск" >> "$LOGFILE"
    exit 0
fi

log "🚀 Запуск tag.sh"

tag_dir() {
    local search_path="$1"
    shift
    find "$search_path" "$@" -type f -iname "*.mp4" | while read -r file; do
        # Используем полный путь как ключ, чтобы не путать одноимённые
        # эпизоды разных сериалов/сезонов
        if grep -Fxq "$file" "$TAGGED_DB"; then
            continue
        fi

        log "🔎 Обработка: $file"

        # Запускаем Python-теггер
        python3 /scripts/tmdb_tagger.py "$file"

        # Если скрипт отработал (не упал), считаем попытку совершенной
        # (даже если фильм не найден, чтобы не долбить API вечно)
        echo "$file" >> "$TAGGED_DB"
    done
}

# Фильмы лежат прямо в DIR_MOVIES
tag_dir "$DIR_MOVIES" -maxdepth 1

# Сериалы organized rename.sh как TV/ShowName/Season X/Show - sXXeYY.mp4
tag_dir "$DIR_TV" -mindepth 3 -maxdepth 3
