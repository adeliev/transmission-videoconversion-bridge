#!/bin/bash

# === move.sh: Перемещение из загрузок в библиотеку ===

# Пути ВНУТРИ контейнера
DEST_ROOT="/media/Downloads/Movies"
DEST_MP4="$DEST_ROOT/MP4"
DEST_MKV="$DEST_ROOT/MKV"
DEST_AVI="$DEST_ROOT/AVI"
DEST_DOWNLOADS="/media/Downloads"
DEST_TVSHOWS="/media/Downloads/TV-Shows"
DEST_TVSHOWS_MKV="$DEST_TVSHOWS/MKV"
DEST_TVSHOWS_AVI="$DEST_TVSHOWS/AVI"
DEST_TVSHOWS_MP4="$DEST_TVSHOWS/MP4"

# Лог файл
LOGFILE="/logs/move.log"

# Создаем необходимые папки
mkdir -p "$DEST_MP4" "$DEST_MKV" "$DEST_AVI" "$DEST_DOWNLOADS" "$DEST_TVSHOWS_MKV" "$DEST_TVSHOWS_AVI" "$DEST_TVSHOWS_MP4"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"

# Функция определения сериала
is_tv_show() {
    local name="$1"
    # Проверяем паттерны: season, сезон, s01e01, s01.e01, s1_e1,
    # а также "(NN сер.)" - формат некоторых русских раздач
    # (например "Кухня-2 (01 сер.).mkv")
    if echo "$name" | grep -qiE '(season|сезон|s[0-9]{1,2}[._ -]*e[0-9]{1,2}|[0-9]{1,3}[ ._-]*сер\.?[ )])'; then
        return 0  # это сериал
    fi
    return 1  # не сериал
}

# Transmission передает переменные среды
INPUT_DIR="${TR_TORRENT_DIR:-$1}"
INPUT_NAME="${TR_TORRENT_NAME:-$2}"

if [ -z "$INPUT_DIR" ]; then
    INPUT_FULL_PATH="$1"
else
    INPUT_FULL_PATH="$INPUT_DIR/$INPUT_NAME"
fi

log "🟢 Запуск. Входные данные: $INPUT_FULL_PATH"

# Разбираем "богатое" имя торрента один раз (для всех файлов в нём общее) —
# пригодится дальше при переименовании (item 4).
# TR_TORRENT_NAME на этот момент (torrent-done) уже перезаписан реальным
# именем файла из метаданных — исходное описательное имя магнета
# сохранено заранее хуком capture_torrent_name.sh (script-torrent-added).
TORRENT_INFO_JSON=""
RICH_NAME=""
if [ -n "$TR_TORRENT_HASH" ] && [ -f "/config/torrent_names/$TR_TORRENT_HASH.txt" ]; then
    RICH_NAME=$(cat "/config/torrent_names/$TR_TORRENT_HASH.txt")
fi
[ -z "$RICH_NAME" ] && RICH_NAME="$INPUT_NAME"

if [ -n "$RICH_NAME" ]; then
    TORRENT_INFO_JSON=$(python3 /scripts/parse_torrent_name.py "$RICH_NAME" 2>>"$LOGFILE")
fi

# Сериал или фильм - решаем ОДИН раз для всего торрента, по имени
# торрента (is_tv из parse_torrent_name.py, который смотрит на
# "Сезон: N" в структурированном имени), а не по каждому файлу
# отдельно - имена файлов внутри раздачи часто вообще не содержат
# признаков сериала (например "1.Отель Элеон 2016.WEB-DL.(720p).mkv").
IS_SHOW=0
if [ -n "$TORRENT_INFO_JSON" ]; then
    is_tv_val=$(echo "$TORRENT_INFO_JSON" | python3 -c "
import json, sys
try:
    print(bool(json.load(sys.stdin).get('is_tv')))
except Exception:
    print(False)
" 2>/dev/null)
    [ "$is_tv_val" = "True" ] && IS_SHOW=1
elif echo "$RICH_NAME" | grep -qiE '(сезон|сезоны|season|seasons)'; then
    # Фолбэк, если сайдкара/имени торрента не нашлось вовсе - грубая
    # проверка по сырому имени
    IS_SHOW=1
fi

# Сохраняет разобранное имя торрента рядом с перемещённым файлом,
# чтобы rename.sh/tag.sh могли использовать его позже
save_torrent_info() {
    local target_path="$1"
    [ -z "$TORRENT_INFO_JSON" ] && return
    echo "$TORRENT_INFO_JSON" > "${target_path}.torrentinfo.json"
}

process_file() {
    local file_path="$1"
    local override_base="$2"
    local filename=$(basename "$file_path")
    local ext="${filename##*.}"
    local target_filename="$filename"

    if [ -n "$override_base" ]; then
        target_filename="$override_base.$ext"
        log "🔢 Номер серии определён по маске имён: $filename -> $target_filename"
    fi

    log "🔎 Обработка файла: $filename"

    # Проверяем, является ли файл/папка сериалом. Приоритет - решение
    # по имени торрента (IS_SHOW), имя/папка файла - доп. подстраховка
    local parent_dir=$(dirname "$file_path")
    local parent_name=$(basename "$parent_dir")
    local is_show=0

    if [ "$IS_SHOW" -eq 1 ] || is_tv_show "$filename" || is_tv_show "$parent_name"; then
        is_show=1
        log "📺 Обнаружен сериал!"
    fi

    # Определяем целевую папку
    local target_dir

    if [ $is_show -eq 1 ]; then
        # Сериалы идут в TV-Shows с разделением по форматам
        case "$ext" in
            [Mm][Kk][Vv])
                target_dir="$DEST_TVSHOWS_MKV"
                ;;
            [Aa][Vv][Ii])
                target_dir="$DEST_TVSHOWS_AVI"
                ;;
            *)
                target_dir="$DEST_TVSHOWS_MP4"
                ;;
        esac
    else
        # Фильмы идут в обычные папки с правильным распределением по форматам
        case "$ext" in
            [Mm][Kk][Vv])
                target_dir="$DEST_MKV"
                ;;
            [Aa][Vv][Ii])
                target_dir="$DEST_AVI"
                ;;
            [Mm][Pp]4|[Mm]4[Vv])
                target_dir="$DEST_MP4"
                ;;
            *)
                # По умолчанию MKV для неизвестных форматов
                target_dir="$DEST_MKV"
                ;;
        esac
    fi

    local target_path="$target_dir/$target_filename"

    # Если файл уже там, ничего не делаем
    if [ -f "$target_path" ]; then
        log "⚠️  Файл уже в библиотеке: $target_filename"
        return
    fi

    log "📦 Перемещение: $filename -> $target_dir/$target_filename"
    mv "$file_path" "$target_path"

    if [ $? -eq 0 ]; then
        log "✅ Успешно перемещен в: $target_path"
        save_torrent_info "$target_path"
    else
        log "❌ Ошибка перемещения файла $file_path"
    fi
}

# Ищет по EPISODE_PLAN (см. ниже) переопределение имени для файла,
# определённое по общей маске "счётчика" в именах (plan_tv_episode_names.py)
lookup_episode_override() {
    local target="$1" path override
    while IFS='|' read -r path override; do
        [ "$path" = "$target" ] && { echo "$override"; return; }
    done <<< "$EPISODE_PLAN"
}

if [ -d "$INPUT_FULL_PATH" ]; then
    # Подсчитываем видео файлы в папке
    video_count=$(find "$INPUT_FULL_PATH" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.m4v" \) | wc -l)

    if [ $video_count -gt 0 ]; then
        # Для однозначно односезонных сериалов (season_from == season_to)
        # пробуем определить номера серий по общей маске имён файлов -
        # на случай, если в них нет ни sXXeYY, ни "NN сер." (см.
        # plan_tv_episode_names.py). Безопасно ничего не делает для
        # фильмов, многосезонных паков и раздач без такой маски.
        EPISODE_PLAN=""
        if [ "$IS_SHOW" -eq 1 ] && [ "$video_count" -ge 2 ] && [ -n "$TORRENT_INFO_JSON" ]; then
            mapfile -t VIDEO_FILES < <(find "$INPUT_FULL_PATH" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.m4v" \))
            EPISODE_PLAN=$(echo "$TORRENT_INFO_JSON" | python3 /scripts/plan_tv_episode_names.py "${VIDEO_FILES[@]}" 2>>"$LOGFILE")
        fi

        # Есть видео файлы - обрабатываем их
        find "$INPUT_FULL_PATH" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.m4v" \) | while read -r video_file; do
            override=""
            [ -n "$EPISODE_PLAN" ] && override=$(lookup_episode_override "$video_file")
            process_file "$video_file" "$override"
        done
        # Удаляем папку торрента
        rm -rf "$INPUT_FULL_PATH"
        log "🗑️  Папка торрента удалена: $INPUT_FULL_PATH"
    else
        # Нет видео файлов - перемещаем всю папку в Downloads
        log "📂 Нет видео файлов. Перемещение папки в Downloads..."
        folder_name=$(basename "$INPUT_FULL_PATH")
        mv "$INPUT_FULL_PATH" "$DEST_DOWNLOADS/$folder_name"
        if [ $? -eq 0 ]; then
            log "✅ Папка перемещена в: $DEST_DOWNLOADS/$folder_name"
        else
            log "❌ Ошибка перемещения папки в Downloads"
        fi
    fi
elif [ -f "$INPUT_FULL_PATH" ]; then
    filename=$(basename "$INPUT_FULL_PATH")
    ext="${filename##*.}"

    # Проверяем, является ли файл видео (используем case для совместимости с sh)
    case "$ext" in
        [Aa][Vv][Ii]|[Mm][Kk][Vv]|[Mm][Pp]4|[Mm]4[Vv])
            process_file "$INPUT_FULL_PATH"
            ;;
        *)
            # Не видео файл - перемещаем в Downloads
            log "📄 Файл не является видео ($ext). Перемещение в Downloads..."
            mv "$INPUT_FULL_PATH" "$DEST_DOWNLOADS/$filename"
            if [ $? -eq 0 ]; then
                log "✅ Файл перемещен в: $DEST_DOWNLOADS/$filename"
            else
                log "❌ Ошибка перемещения файла в Downloads"
            fi
            ;;
    esac
else
    log "❌ Ошибка: Путь не найден $INPUT_FULL_PATH"
fi

# Удаляем торрент из Transmission (файлы уже перемещены в библиотеку)
if [ -n "$TR_TORRENT_HASH" ]; then
    log "🗑️  Удаление торрента $TR_TORRENT_NAME из Transmission..."
    transmission-remote -n "$USER:$PASS" -t "$TR_TORRENT_HASH" --remove
    if [ $? -eq 0 ]; then
        log "✅ Торрент удалён из Transmission"
    else
        log "❌ Ошибка удаления торрента из Transmission"
    fi
    rm -f "/config/torrent_names/$TR_TORRENT_HASH.txt"
fi

log "🏁 Готово."
