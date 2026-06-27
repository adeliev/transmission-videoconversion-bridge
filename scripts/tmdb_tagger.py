#!/usr/bin/env python3
import sys
import os
import re
import requests
import subprocess

# === КОНФИГУРАЦИЯ ===
API_KEY_FILE = "/config/tmdb_api_key.txt"
LOG_FILE = "/logs/tag.log"
POSTER_SIZE = "w780" # 780x1170 (max 1000x1500)

def log(message):
    with open(LOG_FILE, "a") as f:
        import datetime
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        f.write(f"{timestamp} - {message}\n")
    print(message)

def get_api_key():
    if not os.path.exists(API_KEY_FILE):
        log("❌ Ошибка: Файл с ключом не найден.")
        return None
    with open(API_KEY_FILE, "r") as f:
        key = f.read().strip()
    if not key or "YOUR_TMDB" in key:
        return None
    return key

def parse_filename(filename):
    name = os.path.splitext(filename)[0]
    year = None
    is_tv = bool(re.search(r'[Ss]\d{2}[Ee]\d{2}', name))
    match = re.search(r'\(?(19|20)\d{2}\)?', name)
    if match:
        year = match.group(0).strip('()')
        name = name[:match.start()].strip()
    name = name.replace('.', ' ').strip()
    return name, year, is_tv

def search_tmdb(title, year, is_tv, api_key):
    # Пробуем TV, если есть признаки сериала, иначе сначала Movie
    search_types = ["tv", "movie"] if is_tv else ["movie", "tv"]
    for s_type in search_types:
        url = f"https://api.themoviedb.org/3/search/{s_type}"
        params = {"api_key": api_key, "query": title, "language": "ru-RU", "include_adult": "false"}
        if year: params["year" if s_type == "movie" else "first_air_date_year"] = year
        try:
            r = requests.get(url, params=params)
            data = r.json()
            if data.get("results"):
                res = data["results"][0]
                res['s_type'] = s_type
                return res
        except Exception: pass
    return None

def download_poster(poster_path):
    if not poster_path:
        log("🖼️  Постер отсутствует в TMDB")
        return None
    url = f"https://image.tmdb.org/t/p/{POSTER_SIZE}{poster_path}"
    temp_img = "/tmp/poster.jpg"
    try:
        r = requests.get(url, stream=True)
        if r.status_code == 200:
            with open(temp_img, 'wb') as f: f.write(r.content)
            log("🖼️  Постер загружен")
            return temp_img
    except Exception:
        log("⚠️  Ошибка загрузки постера")
    return None

def tag_file(file_path, meta, poster_img):
    temp_file = file_path + ".temp.mp4"
    title = meta.get('title') or meta.get('name') or ''
    overview = meta.get('overview', '')
    date = meta.get('release_date') or meta.get('first_air_date') or ''
    year = date.split('-')[0] if date else ''
    poster_status = "с постером" if poster_img else "без постера"
    log(f"🏷️  Тегируем: '{title}' ({year}) {poster_status}")
    cmd = ["ffmpeg", "-i", file_path]
    if poster_img:
        cmd += ["-i", poster_img, "-map", "0", "-map", "1", "-disposition:v:1", "attached_pic"]
    else:
        cmd += ["-map", "0"]
    cmd += ["-c", "copy", "-metadata", f"title={title}", "-metadata", f"date={year}", "-metadata", f"comment={overview}", "-metadata", "language=rus", "-loglevel", "error", "-y", temp_file]
    try:
        subprocess.run(cmd, check=True)
        os.replace(temp_file, file_path)
        return True
    except Exception as e:
        log(f"❌ Ошибка ffmpeg: {e}")
        if os.path.exists(temp_file): os.remove(temp_file)
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(1)
    file_path = sys.argv[1]
    api_key = get_api_key()
    if not api_key: sys.exit(0)
    name, year, is_tv = parse_filename(os.path.basename(file_path))
    year_str = f", Year: {year}" if year else ", Year: None"
    log(f"🔍 Поиск в TMDB: '{name}' (TV: {is_tv}{year_str})...")
    meta = search_tmdb(name, year, is_tv, api_key)
    if meta:
        poster_img = download_poster(meta.get('poster_path'))
        tag_file(file_path, meta, poster_img)
        if poster_img and os.path.exists(poster_img): os.remove(poster_img)
    else: log(f"⚠️ Не найдено: {name}")
