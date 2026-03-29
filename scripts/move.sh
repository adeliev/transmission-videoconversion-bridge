#!/bin/bash

# === move.sh: Перемещение из загрузок в библиотеку ===

# Пути ВНУТРИ контейнера
DEST_ROOT="/movies"
DEST_MP4="$DEST_ROOT/MP4"
DEST_MKV="$DEST_ROOT/MKV"
DEST_AVI="$DEST_ROOT/AVI"
DEST_DOWNLOADS="/downloads_host"
DEST_TVSHOWS="/downloads_host/TV-Shows"
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

# Функция определения сериала
is_tv_show() {
    local name="$1"
    # Проверяем паттерны: season, сезон, s01e01, s01.e01, s1_e1 и т.д.
    if echo "$name" | grep -qiE '(season|сезон|s[0-9]{1,2}[._ -]*e[0-9]{1,2})'; then
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

process_file() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local ext="${filename##*.}"

    log "🔎 Обработка файла: $filename"

    # Проверяем, является ли файл/папка сериалом
    local parent_dir=$(dirname "$file_path")
    local parent_name=$(basename "$parent_dir")
    local is_show=0

    if is_tv_show "$filename" || is_tv_show "$parent_name"; then
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

    local target_path="$target_dir/$filename"

    # Если файл уже там, ничего не делаем
    if [ -f "$target_path" ]; then
        log "⚠️  Файл уже в библиотеке: $filename"
        return
    fi

    log "📦 Перемещение: $filename -> $target_dir/"
    mv "$file_path" "$target_path"

    if [ $? -eq 0 ]; then
        log "✅ Успешно перемещен в: $target_path"
    else
        log "❌ Ошибка перемещения файла $file_path"
    fi
}

if [ -d "$INPUT_FULL_PATH" ]; then
    # Подсчитываем видео файлы в папке
    video_count=$(find "$INPUT_FULL_PATH" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.m4v" \) | wc -l)

    if [ $video_count -gt 0 ]; then
        # Есть видео файлы - обрабатываем их
        find "$INPUT_FULL_PATH" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.m4v" \) | while read -r video_file; do
            process_file "$video_file"
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

log "🏁 Готово."
