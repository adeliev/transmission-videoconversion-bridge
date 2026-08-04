#!/bin/bash

# === convert.sh: Умная Конвертация MKV/AVI -> MP4 ===

MOV_MKV="/media/Downloads/Movies/MKV"
MOV_AVI="/media/Downloads/Movies/AVI"
MOV_MP4="/media/Downloads/Movies/MP4"
TV_MKV="/media/Downloads/TV-Shows/MKV"
TV_AVI="/media/Downloads/TV-Shows/AVI"
TV_MP4="/media/Downloads/TV-Shows/MP4"

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

# Не даём двум экземплярам convert.sh работать одновременно - см. tag.sh
exec 200>"/config/.convert.sh.lock"
if ! flock -n 200; then
    log "⏭️  Уже выполняется другой convert.sh, пропуск"
    exit 0
fi

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
    
    # Массив, НЕ строка - имена дорожек вроде "HDRezka, MVO" или
    # "Light Breeze" содержат пробелы/запятые и сломали бы word-split
    # при обычной подстановке неэкранированной переменной
    local mapping_args=()
    mapfile -t mapping_args < <(python3 /scripts/get_ffmpeg_map.py "$source_file")
    if [ ${#mapping_args[@]} -eq 0 ]; then
        mapping_args=("-map" "0:v:0" "-map" "0:a:0?")
    fi

    # ВАЖНО: временный файл - НЕ в $output_dir напрямую, а в отдельной
    # подпапке .converting. rename.sh сканирует $output_dir с
    # -maxdepth 1, но если конвертация долгая (для сезона это часто
    # десятки минут), а rename.sh/monitor.sh запустили не в свою
    # очередь (например, вручную во время работы convert.sh) - он мог
    # подхватить ещё не готовый tmp_*.mp4 и переименовать/увести его
    # прямо во время записи ffmpeg. Проверено на реальном случае -
    # получилась "серия" несуществующего сериала "tmp Ш ...".
    local tmp_dir="$output_dir/.converting"
    mkdir -p "$tmp_dir"
    local tmp_mp4="$tmp_dir/tmp_$base.mp4"

    case "$ext" in
        [Mm][Kk][Vv])
            ffmpeg -i "$source_file" "${mapping_args[@]}" -c:v copy -c:a aac -b:a 256k -ac 2 -c:s mov_text "$tmp_mp4" -y < /dev/null >> "/logs/ffmpeg.log" 2>&1
            ;;
        [Aa][Vv][Ii])
            local bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv="p=0" "$source_file")
            [ -z "$bitrate" ] || [ "$bitrate" = "N/A" ] && bitrate="2000000"
            local bitrate_kbps="$((bitrate / 1000))k"
            ffmpeg -i "$source_file" "${mapping_args[@]}" -c:v libx264 -b:v "$bitrate_kbps" -c:a aac -b:a 256k -ac 2 -c:s mov_text "$tmp_mp4" -y < /dev/null >> "/logs/ffmpeg.log" 2>&1
            ;;
        *)
            ffmpeg -i "$source_file" "${mapping_args[@]}" -c copy -c:s mov_text "$tmp_mp4" -y < /dev/null >> "/logs/ffmpeg.log" 2>&1
            ;;
    esac

    if [ $? -eq 0 ]; then
        mv "$tmp_mp4" "$output_dir/$base.mp4"
        # Переносим "богатое" имя торрента (item 4) вместе с файлом,
        # иначе оно осиротеет в ArchivedSources вместе с исходником
        if [ -f "$source_file.torrentinfo.json" ]; then
            mv "$source_file.torrentinfo.json" "$output_dir/$base.mp4.torrentinfo.json"
        fi
        local archive_base="/media/Downloads/ArchivedSources"
        local archive_dir="$archive_base"
        [[ "$output_dir" == "/media/Downloads/Movies/MP4" ]] && archive_dir="$archive_base/Movies" || archive_dir="$archive_base/TV-Shows"
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
    if [[ "$file" == *"/Downloads/Movies/"* ]]; then
        convert_file "$file" "$MOV_MP4"
    else
        convert_file "$file" "$TV_MP4"
    fi
done
