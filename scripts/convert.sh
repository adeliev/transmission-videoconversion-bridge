#!/bin/bash

# === convert.sh: Конвертация MKV/AVI -> MP4 ===

DIR_MKV="/movies/MKV"
DIR_AVI="/movies/AVI"
DIR_MP4="/movies/MP4"
LOGFILE="/logs/convert.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

# Функция определения сериала
is_tv_show() {
    local name="$1"
    # Проверяем паттерны: season, сезон, s01e01, s1e1, и т.д.
    if echo "$name" | grep -qiE '(season|сезон|s[0-9]{1,2}e[0-9]{1,2})'; then
        return 0  # это сериал
    fi
    return 1  # не сериал
}

convert_file() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local base="${filename%.*}"
    local ext="${filename##*.}"

    # Проверяем, является ли файл сериалом - их НЕ конвертируем
    if is_tv_show "$filename"; then
        log "📺 Пропуск сериала: $filename (сериалы не конвертируются)"
        return
    fi

    # 1. Проверяем наличие "грязного" MP4 (вдруг только что сконвертировали, но не переименовали)
    local dirty_mp4="$DIR_MP4/$base.mp4"
    if [ -f "$dirty_mp4" ]; then
        return 
    fi

    # 2. Проверяем наличие "чистого" MP4 (чтобы не делать дубликаты)
    local clean_base=$(/scripts/clean_name.py "$base")
    local clean_mp4="$DIR_MP4/$clean_base.mp4"
    if [ -f "$clean_mp4" ]; then
        return
    fi

    # Если мы здесь, значит файла нет ни в каком виде. Конвертируем!
    log "🎬 Начинаем конвертацию: $filename"
    
    # Конвертируем во временный файл
    local tmp_mp4="$DIR_MP4/tmp_$base.mp4"

    # Используем case для совместимости с sh
    case "$ext" in
        [Mm][Kk][Vv])
            # MKV: Copy Video, Convert Audio, No Subs
            ffmpeg -i "$source_file" -map 0:v -map 0:a -c:v copy -c:a aac -b:a 256k -ac 2 -sn "$tmp_mp4" -y >> "/logs/ffmpeg.log" 2>&1
            ;;
        [Aa][Vv][Ii])
            # AVI: Convert Video & Audio
            local bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv="p=0" "$source_file")
            [ -z "$bitrate" ] && bitrate="2000000"
            local bitrate_kbps="$((bitrate / 1000))k"
            ffmpeg -i "$source_file" -c:v libx264 -b:v "$bitrate_kbps" -c:a aac -b:a 256k -ac 2 -sn "$tmp_mp4" -y >> "/logs/ffmpeg.log" 2>&1
            ;;
        *)
            ffmpeg -i "$source_file" -map 0:v -map 0:a -c copy -sn "$tmp_mp4" -y >> "/logs/ffmpeg.log" 2>&1
            ;;
    esac

    if [ $? -eq 0 ]; then
        # Переименовываем tmp в "грязный" MP4.
        # Следующий шаг (rename.sh) сделает из него "чистый".
        mv "$tmp_mp4" "$dirty_mp4"
        log "✅ Сконвертирован: $dirty_mp4"
    else
        log "❌ Ошибка конвертации: $filename"
        rm -f "$tmp_mp4"
    fi
}

# Обходим папки
find "$DIR_MKV" -maxdepth 1 -type f -iname "*.mkv" | while read -r file; do convert_file "$file"; done
find "$DIR_AVI" -maxdepth 1 -type f -iname "*.avi" | while read -r file; do convert_file "$file"; done