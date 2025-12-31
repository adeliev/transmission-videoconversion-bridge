#!/usr/bin/env python3
import sys
import os
import re
import requests
import subprocess

# === КОНФИГУРАЦИЯ ===
API_KEY_FILE = "/config/tmdb_api_key.txt"
LOG_FILE = "/logs/tag.log"

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
        lines = f.readlines()
    
    key = ""
    for line in lines:
        line = line.strip()
        if line and not line.startswith("#"):
            key = line
            break
            
    if not key or "YOUR_TMDB" in key or len(key) < 10:
        log("⚠️ API Key не настроен. Пропустите этот шаг.")
        return None
    return key

def parse_filename(filename):
    # Пытаемся вытащить Название и Год (опционально)
    # Ищем год в скобках или просто 4 цифры
    name = os.path.splitext(filename)[0]
    year = None
    
    match = re.search(r'\(?(19|20)\d{2}\)?', name)
    if match:
        year = match.group(0).strip('()')
        # Имя - всё что до года
        name = name[:match.start()].strip()
    
    # Очищаем имя от точек и лишнего (используем логику как в clean_name)
    name = name.replace('.', ' ').strip()
    return name, year

def search_tmdb(title, year, api_key):
    url = "https://api.themoviedb.org/3/search/movie"
    params = {
        "api_key": api_key,
        "query": title,
        "language": "ru-RU", # Предпочитаем русский, если есть
        "include_adult": "false"
    }
    if year:
        params["year"] = year

    try:
        r = requests.get(url, params=params)
        r.raise_for_status()
        data = r.json()
        if data["results"]:
            return data["results"][0] # Берем первый результат
        
        # Если искали с годом и не нашли, пробуем без года
        if year:
            del params["year"]
            r = requests.get(url, params=params)
            data = r.json()
            if data["results"]:
                return data["results"][0]
                
    except Exception as e:
        log(f"❌ Ошибка запроса к TMDB: {e}")
    return None

def tag_file(file_path, meta):
    # Формируем метаданные для ffmpeg
    temp_file = file_path + ".temp.mp4"
    
    title = meta.get('title', '')
    overview = meta.get('overview', '')
    release_date = meta.get('release_date', '')
    year = release_date.split('-')[0] if release_date else ''
    
    log(f"🏷️  Тегируем: '{title}' ({year})")

    cmd = [
        "ffmpeg", "-i", file_path,
        "-map", "0",           # Копируем все потоки
        "-c", "copy",          # Без перекодирования (очень быстро)
        "-metadata", f"title={title}",
        "-metadata", f"date={year}",
        "-metadata", f"year={year}", # Для совместимости
        "-metadata", f"comment={overview}",
        "-metadata", f"description={overview}",
        "-metadata", f"synopsis={overview}",
        "-metadata", "language=rus",
        "-loglevel", "error",
        "-y", temp_file
    ]

    try:
        subprocess.run(cmd, check=True)
        # Заменяем оригинал на тегированный файл
        os.replace(temp_file, file_path)
        return True
    except subprocess.CalledProcessError:
        log(f"❌ Ошибка ffmpeg при тегировании {file_path}")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: tmdb_tagger.py <file_path>")
        sys.exit(1)

    file_path = sys.argv[1]
    filename = os.path.basename(file_path)

    api_key = get_api_key()
    if not api_key:
        sys.exit(0)

    name, year = parse_filename(filename)
    log(f"🔍 Поиск в TMDB: '{name}' (Year: {year})...")

    meta = search_tmdb(name, year, api_key)
    
    if meta:
        log(f"✅ Найдено: {meta['id']})")
        tag_file(file_path, meta)
    else:
        log(f"⚠️ Не найдено в TMDB: {name}")
