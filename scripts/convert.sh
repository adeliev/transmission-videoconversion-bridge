#!/bin/bash

# === convert.sh: Умная Конвертация MKV/AVI -> MP4 ===

MOV_MKV="/movies/MKV"
MOV_AVI="/movies/AVI"
MOV_MP4="/movies/MP4"
TV_MKV="/downloads_host/TV-Shows/MKV"
TV_AVI="/downloads_host/TV-Shows/AVI"
TV_MP4="/downloads_host/TV-Shows/MP4"

LOGFILE="/logs/convert.log"

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" >> "$LOGFILE"
}

rotate_log() {
    local f="$1" max=10485760
    [ -f "$f" ] && [ "$(wc -c < "$f")" -gt "$max" ] && tail -n 2000 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

rotate_log "$LOGFILE"
rotate_log "/logs/ffmpeg.log"

convert_file() {
    local source_file="$1"
    local output_dir="$2"
    local filename=$(basename "$source_file")
    local base="${filename%.*}"
    local ext="${filename##*.}"

    # Исправляем базу (берем все кроме последнего расширения)
    local real_base="${filename%.*}"
    [ "$base" != "$real_base" ] && base="$real_base"
    base="${filename%.*}" # В sh это надежнее, но мы сделаем лучше:
    base=$(basename "$source_file" ".$ext")

    [ -f "$output_dir/$base.mp4" ] && return
    local clean_base=$(/scripts/clean_name.py "$base")
    [ -f "$output_dir/$clean_base.mp4" ] && return

    log "🎬 Анализ и конвертация: $filename"
    
    local mapping=$(python3 /scripts/get_ffmpeg_map.py "$source_file")
    if [ -z "$mapping" ]; then mapping="-map 0:v:0 -map 0:a:0?"; fi

    local tmp_mp4="$output_dir/tmp_$base.mp4"

    case "$ext" in
        [Mm][Kk][Vv])
            ffmpeg -i "$source_file" $mapping -c:v copy -c:a aac -b:a 256k -ac 2 -c:s mov_text "$tmp_mp4" -y < /dev/null >> "/logs/ffmpeg.log" 2>&1
            ;;
        [Aa][Vv][Ii])
            local bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv="p=0" "$source_file")
            [ -z "$bitrate" ] || [ "$bitrate" = "N/A" ] && bitrate="2000000"
            local bitrate_kbps="$((bitrate / 1000))k"
            ffmpeg -i "$source_file" $mapping -c:v libx264 -b:v "$bitrate_kbps" -c:a aac -b:a 256k -ac 2 -c:s mov_text "$tmp_mp4" -y < /dev/null >> "/logs/ffmpeg.log" 2>&1
            ;;
        *)
            ffmpeg -i "$source_file" $mapping -c copy -c:s mov_text "$tmp_mp4" -y < /dev/null >> "/logs/ffmpeg.log" 2>&1
            ;;
    esac

    if [ $? -eq 0 ]; then
        mv "$tmp_mp4" "$output_dir/$base.mp4"
        local archive_base="/downloads_host/ArchivedSources"
        local archive_dir="$archive_base"
        [[ "$output_dir" == "/movies/MP4" ]] && archive_dir="$archive_base/Movies" || archive_dir="$archive_base/TV-Shows"
        mkdir -p "$archive_dir"
        mv "$source_file" "$archive_dir/"
        log "✅ Сконвертирован: $filename (исходник в ArchivedSources)"
    else
        log "❌ Ошибка: $filename"
        rm -f "$tmp_mp4"
    fi
}

mkdir -p "$MOV_MP4" "$TV_MP4"
find "$MOV_MKV" "$MOV_AVI" "$TV_MKV" "$TV_AVI" -type f \( -iname "*.mkv" -o -iname "*.avi" \) | while read -r file; do
    if [[ "$file" == *"/movies/"* ]]; then
        convert_file "$file" "$MOV_MP4"
    else
        convert_file "$file" "$TV_MP4"
    fi
done
