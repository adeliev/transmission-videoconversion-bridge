#!/usr/bin/env python3
import sys
import os
import re
import json
import plistlib
import requests
import subprocess
import datetime

# === КОНФИГУРАЦИЯ ===
API_KEY_FILE = "/config/tmdb_api_key.txt"
LOG_FILE = "/logs/tag.log"
POSTER_SIZE = "w780"  # 780x1170 (max 1000x1500)
TMDB_BASE = "https://api.themoviedb.org/3"
LANGUAGE = "ru-RU"  # приоритетный язык метаданных

# Ограничение длины короткого поля "description" (аналог классического
# лимита iTunes на атом desc). Полный текст всегда уходит в "synopsis".
DESCRIPTION_LIMIT = 250

# Имя файла после rename.sh: "Show Name - s01e01.mp4"
TV_EPISODE_RE = re.compile(r'^(.*?)\s*-\s*[Ss](\d{2})[Ee](\d{2})$')

# Страна производства (из имени торрента, см. parse_torrent_name.py) ->
# язык видео-дорожки (ISO 639-2). Ключи те же, что в COUNTRIES там же.
COUNTRY_LANG = {
    "США": "eng", "Великобритания": "eng", "Канада": "eng",
    "Австралия": "eng", "Ирландия": "eng", "Новая Зеландия": "eng",
    "Россия": "rus",
    "Германия": "ger",
    "Испания": "spa", "Мексика": "spa",
    "Франция": "fre",
    "Италия": "ita",
    "Япония": "jpn",
    "Южная Корея": "kor",
    "Китай": "chi",
    "Индия": "hin",
    "Бразилия": "por",
    "Нидерланды": "dut",
    "Швеция": "swe",
    "Норвегия": "nor",
    "Дания": "dan",
    "Финляндия": "fin",
    "Бельгия": "dut",
}


def detect_video_language(countries, name):
    """Язык видео-дорожки: по стране производства (из имени торрента),
    а если стран нет/язык неизвестен - по алфавиту в названии (кириллица
    -> rus, иначе eng, как чаще всего и бывает на практике)."""
    for country in countries or []:
        lang = COUNTRY_LANG.get(country)
        if lang:
            return lang
    return "rus" if re.search(r'[а-яА-ЯёЁ]', name or "") else "eng"

# Сколько актёров класть в iTunMOVI.cast - столько же, сколько в
# эталонном файле, тегированном Subler
CAST_LIMIT = 27

# Внутренний числовой код рейтинга Apple (виден в iTunEXTC как
# "mpaa|R|400|") - подтверждено эмпирически на реальных файлах
MPAA_SCORE = {"G": "100", "PG": "200", "PG-13": "300", "R": "400", "NC-17": "500"}
# Аналогично для сериалов ("us-tv|TV-MA|600|") - подтверждено на Banshee
TVPG_SCORE = {"TV-Y": "100", "TV-Y7": "200", "TV-G": "300", "TV-PG": "400", "TV-14": "500", "TV-MA": "600"}


def log(message):
    with open(LOG_FILE, "a") as f:
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


def load_sidecar(file_path):
    """Читает .torrentinfo.json (см. move.sh/parse_torrent_name.py), если он
    дошёл до этого места по цепочке move->convert->rename. Год в имя файла
    больше не пишется (item 4), поэтому для поиска в TMDB он берётся отсюда.
    """
    sidecar_path = file_path + ".torrentinfo.json"
    if not os.path.exists(sidecar_path):
        return None
    try:
        with open(sidecar_path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def parse_target(file_path):
    """Определяет, фильм это или эпизод сериала, по имени файла."""
    name = os.path.splitext(os.path.basename(file_path))[0]
    sidecar = load_sidecar(file_path)

    m = TV_EPISODE_RE.match(name)
    if m:
        target = {
            "is_tv": True,
            "show": m.group(1).strip(),
            "season": int(m.group(2)),
            "episode": int(m.group(3)),
            "year": None,
            "countries": [],
        }
        if sidecar and sidecar.get("is_tv"):
            target["year"] = sidecar.get("year")
            target["countries"] = sidecar.get("countries") or []
            if sidecar.get("display_title"):
                target["show"] = sidecar["display_title"]
        return target

    if sidecar and not sidecar.get("is_tv") and sidecar.get("display_title"):
        return {
            "is_tv": False,
            "title": sidecar["display_title"],
            "year": sidecar.get("year"),
            "countries": sidecar.get("countries") or [],
        }

    # Фолбэк - имя файла (год в нём теперь тоже не ожидается, но на
    # случай старых/невыясненных файлов проверка не помешает)
    year = None
    match = re.search(r'\(?(19|20)\d{2}\)?', name)
    if match:
        year = match.group(0).strip('()')
        name = name[:match.start()].strip()
    name = name.replace('.', ' ').strip()
    return {"is_tv": False, "title": name, "year": year, "countries": []}


def tmdb_get(path, params, api_key):
    params = {**params, "api_key": api_key, "language": LANGUAGE}
    r = requests.get(f"{TMDB_BASE}{path}", params=params, timeout=15)
    r.raise_for_status()
    return r.json()


def find_crew(crew, job):
    names = [c.get("name") for c in crew if c.get("job") == job and c.get("name")]
    return ", ".join(names) if names else None


def truncate(text, limit=DESCRIPTION_LIMIT):
    if not text or len(text) <= limit:
        return text or ""
    cut = text[:limit].rsplit(" ", 1)[0]
    return cut + "…"


def dedupe_names(names):
    """Убирает повторы (частый случай - один человек в нескольких ролях
    в титрах TMDB), сохраняя порядок первого появления."""
    seen = set()
    result = []
    for name in names:
        if name and name not in seen:
            seen.add(name)
            result.append(name)
    return result


def get_us_certification(release_dates):
    """Возрастной рейтинг US (MPAA) из append_to_response=release_dates.
    Предпочитаем театральный прокат (type 3), иначе первый непустой."""
    for country in release_dates.get("results", []):
        if country.get("iso_3166_1") != "US":
            continue
        entries = country.get("release_dates", [])
        for rd in entries:
            if rd.get("type") == 3 and rd.get("certification"):
                return rd["certification"]
        for rd in entries:
            if rd.get("certification"):
                return rd["certification"]
    return None


def build_itunextc(certification, system="mpaa", score_table=MPAA_SCORE):
    if not certification:
        return None
    score = score_table.get(certification, "000")
    return f"{system}|{certification}|{score}|"


def get_us_tv_rating(content_ratings):
    for r in content_ratings.get("results", []):
        if r.get("iso_3166_1") == "US" and r.get("rating"):
            return r["rating"]
    return None


def build_itunmovi(cast, directors, producers, screenwriters, studio):
    data = {}
    if cast:
        data["cast"] = [{"name": n} for n in cast[:CAST_LIMIT]]
    if directors:
        data["directors"] = [{"name": n} for n in directors]
    if producers:
        data["producers"] = [{"name": n} for n in producers]
    if screenwriters:
        data["screenwriters"] = [{"name": n} for n in screenwriters]
    if studio:
        data["studio"] = studio
    if not data:
        return None
    return plistlib.dumps(data, fmt=plistlib.FMT_XML).decode("utf-8")


def fetch_movie_meta(target, api_key):
    # Год из имени торрента иногда не совпадает с тем, что у TMDB
    # (постпродакшн/фестивальный vs широкий релиз и т.п.), а TMDB
    # фильтрует по году строго (см. баг с TV-сериалами и
    # first_air_date_year) - сначала без года, год - фолбэк, только
    # если пустой поиск.
    base_params = {"query": target["title"], "include_adult": "false"}
    data = tmdb_get("/search/movie", base_params, api_key)
    results = data.get("results")
    if not results and target["year"]:
        data = tmdb_get("/search/movie", {**base_params, "year": target["year"]}, api_key)
        results = data.get("results")
    if not results:
        return None
    movie_id = results[0]["id"]
    details = tmdb_get(
        f"/movie/{movie_id}", {"append_to_response": "credits,release_dates"}, api_key
    )

    credits_ = details.get("credits", {})
    crew = credits_.get("crew", [])
    cast = [c["name"] for c in credits_.get("cast", []) if c.get("name")]
    overview = details.get("overview", "")
    title = details.get("title") or target["title"]
    date = details.get("release_date", "")
    genres = ", ".join(g["name"] for g in details.get("genres", []))
    director = find_crew(crew, "Director")
    composer = find_crew(crew, "Original Music Composer")

    directors_list = dedupe_names(c["name"] for c in crew if c.get("job") == "Director")
    producers = dedupe_names(c["name"] for c in crew if c.get("job") == "Producer")
    exec_producers = dedupe_names(c["name"] for c in crew if c.get("job") == "Executive Producer")
    screenwriters = dedupe_names(
        c["name"] for c in crew if c.get("job") in ("Screenplay", "Writer", "Story")
    )
    studio = ", ".join(c["name"] for c in details.get("production_companies", []))
    certification = get_us_certification(details.get("release_dates", {}))

    tags = {
        "title": title,
        "artist": director or "",
        "composer": composer or "",
        "comment": overview,
        "genre": genres,
        "date": f"{date}T12:00:00Z" if date else "",
        "director": director or "",
        "description": truncate(overview),
        "synopsis": overview,
        "media_type": "9",
    }

    itunextc = build_itunextc(certification)
    if itunextc:
        tags["itunextc"] = itunextc
    itunmovi = build_itunmovi(cast, directors_list, producers, screenwriters, studio)
    if itunmovi:
        tags["itunmovi"] = itunmovi
    if exec_producers:
        tags["xpd"] = ", ".join(exec_producers)

    return {
        "is_tv": False,
        "poster_path": details.get("poster_path"),
        "countries": target.get("countries", []),
        "tags": tags,
    }


def fetch_tv_meta(target, api_key):
    # ВАЖНО: "year" в сайдкаре - это год выпуска КОНКРЕТНОГО СЕЗОНА
    # (из имени торрента "Отель Элеон / Сезон: 2 / ... [2017, ...]"),
    # а TMDB'шный first_air_date_year фильтрует по году ПРЕМЬЕРЫ ШОУ
    # целиком (сезон 1) - для второго сезона и далее это разные годы,
    # и TMDB просто не находит ничего (не ранжирует ниже - исключает
    # полностью). Поэтому сначала ищем БЕЗ фильтра, и только если
    # ничего не нашлось - пробуем с годом как узкий фолбэк.
    base_params = {"query": target["show"], "include_adult": "false"}
    data = tmdb_get("/search/tv", base_params, api_key)
    results = data.get("results")
    if not results and target.get("year"):
        data = tmdb_get("/search/tv", {**base_params, "first_air_date_year": target["year"]}, api_key)
        results = data.get("results")
    if not results:
        return None
    tv_id = results[0]["id"]
    show = tmdb_get(f"/tv/{tv_id}", {"append_to_response": "credits,content_ratings"}, api_key)

    season, episode = target["season"], target["episode"]
    try:
        ep = tmdb_get(
            f"/tv/{tv_id}/season/{season}/episode/{episode}",
            {"append_to_response": "credits"},
            api_key,
        )
    except requests.HTTPError:
        return None

    show_name = show.get("name") or target["show"]
    genres = ", ".join(g["name"] for g in show.get("genres", []))
    networks = ", ".join(n["name"] for n in show.get("networks", []))
    overview = ep.get("overview", "")
    ep_title = ep.get("name") or f"Серия {episode}"
    air_date = ep.get("air_date", "")
    crew = ep.get("credits", {}).get("crew", [])
    director = find_crew(crew, "Director")
    episode_id = f"{season}{episode:02d}"

    # cast - актёры шоу (не эпизода), directors/screenwriters - конкретной
    # серии - именно так устроен эталонный файл (Banshee)
    cast = [c["name"] for c in show.get("credits", {}).get("cast", []) if c.get("name")]
    directors_list = dedupe_names(c["name"] for c in crew if c.get("job") == "Director")
    screenwriters = dedupe_names(
        c["name"] for c in crew if c.get("job") in ("Screenplay", "Writer", "Story")
    )
    certification = get_us_tv_rating(show.get("content_ratings", {}))

    tags = {
        "title": ep_title,
        "artist": show_name,
        "album_artist": show_name,
        "album": f"{show_name}, Season {season}",
        "genre": genres,
        "date": f"{air_date}T12:00:00Z" if air_date else "",
        "director": director or "",
        "track": str(episode),
        "show": show_name,
        "network": networks,
        "episode_id": episode_id,
        "season_number": str(season),
        "episode_sort": str(episode),
        "description": truncate(overview),
        "synopsis": overview,
        "media_type": "10",
    }

    itunextc = build_itunextc(certification, system="us-tv", score_table=TVPG_SCORE)
    if itunextc:
        tags["itunextc"] = itunextc
    itunmovi = build_itunmovi(cast, directors_list, [], screenwriters, "")
    if itunmovi:
        tags["itunmovi"] = itunmovi

    return {
        "is_tv": True,
        "poster_path": show.get("poster_path"),
        "countries": target.get("countries", []),
        "tags": tags,
    }


def download_poster(poster_path):
    if not poster_path:
        log("🖼️  Постер отсутствует в TMDB")
        return None
    url = f"https://image.tmdb.org/t/p/{POSTER_SIZE}{poster_path}"
    temp_img = "/tmp/poster.jpg"
    try:
        r = requests.get(url, stream=True, timeout=15)
        if r.status_code == 200:
            with open(temp_img, 'wb') as f:
                f.write(r.content)
            log("🖼️  Постер загружен")
            return temp_img
    except Exception:
        log("⚠️  Ошибка загрузки постера")
    return None


def get_existing_stream_metadata(file_path):
    """ffmpeg -c copy НЕ переносит произвольные per-stream атомы (title/name)
    при повторном ремуксе, даже без -map_metadata -1 (только language
    сохраняется сам по себе) - поэтому перед своим (уже вторым по счёту
    после convert.sh) ремуксом считываем то, что там уже выставлено
    get_ffmpeg_map.py, и переносим явно, иначе очистка имён дорожек
    (item 3) слетает молча.
    """
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", file_path],
            capture_output=True, text=True, check=True,
        )
        info = json.loads(r.stdout)
    except Exception:
        return []

    args = []
    a_idx = s_idx = 0
    for stream in info.get("streams", []):
        codec_type = stream.get("codec_type")
        tags = stream.get("tags", {}) or {}
        lang = tags.get("language")
        title = tags.get("title") or tags.get("name")
        if codec_type == "audio":
            if lang:
                args += [f"-metadata:s:a:{a_idx}", f"language={lang}"]
            if title:
                args += [f"-metadata:s:a:{a_idx}", f"title={title}"]
            a_idx += 1
        elif codec_type == "subtitle":
            if lang:
                args += [f"-metadata:s:s:{s_idx}", f"language={lang}"]
            if title:
                args += [f"-metadata:s:s:{s_idx}", f"title={title}"]
            s_idx += 1
    return args


# ffmpeg не умеет писать эти атомы через -metadata (молча игнорирует) -
# director/xpd это обычные "©"-атомы вне стандартной таблицы ffmpeg,
# а iTunEXTC/iTunMOVI - произвольные freeform-атомы ("----"), которые
# ffmpeg вообще не поддерживает на запись. Дописываем их через mutagen.
FFMPEG_UNSUPPORTED_KEYS = {"director", "xpd", "itunextc", "itunmovi"}


def set_unsupported_tags(file_path, tags):
    from mutagen.mp4 import MP4, MP4FreeForm

    director = tags.get("director")
    xpd = tags.get("xpd")
    itunextc = tags.get("itunextc")
    itunmovi = tags.get("itunmovi")

    if not any([director, xpd, itunextc, itunmovi]):
        return

    mp4 = MP4(file_path)
    if mp4.tags is None:
        mp4.add_tags()

    if director:
        mp4.tags["\xa9dir"] = [director]
    if xpd:
        mp4.tags["\xa9xpd"] = [xpd]
    if itunextc:
        mp4.tags["----:com.apple.iTunes:iTunEXTC"] = [MP4FreeForm(itunextc.encode("utf-8"))]
    if itunmovi:
        mp4.tags["----:com.apple.iTunes:iTunMOVI"] = [MP4FreeForm(itunmovi.encode("utf-8"))]

    mp4.save()


def tag_file(file_path, meta, poster_img):
    # PID в имени - defense-in-depth на случай конкурентного запуска
    # (основная защита - flock в tag.sh), чтобы два процесса не писали
    # в один и тот же временный файл
    temp_file = f"{file_path}.{os.getpid()}.temp.mp4"
    tags = meta["tags"]
    poster_status = "с постером" if poster_img else "без постера"
    log(f"🏷️  Тегируем: '{tags['title']}' {poster_status}")

    # Имя видео-дорожки = имя файла без расширения (оригинальное
    # название фильма/серии, полученное на шаге переименования)
    video_title = os.path.splitext(os.path.basename(file_path))[0]

    # Язык видео-дорожки - по стране производства (item: языки дорожек)
    video_lang = detect_video_language(meta.get("countries"), video_title)

    # Сохраняем то, что уже выставил get_ffmpeg_map.py на аудио/субтитрах
    # (иначе -map_metadata -1 ниже их сотрёт вместе с мусором источника)
    stream_meta_args = get_existing_stream_metadata(file_path)

    # "0:v:0" (не "0") - иначе при повторном тегировании уже тегированного
    # файла старая обложка (сама по себе видео-поток) попадает в маппинг
    # как обычная дорожка без attached_pic, а рядом добавляется ещё одна
    # новая - и так плодятся дубли обложек с каждым перезапуском
    cmd = ["ffmpeg", "-i", file_path]
    if poster_img:
        cmd += [
            "-i", poster_img,
            "-map", "0:v:0", "-map", "0:a", "-map", "0:s?", "-map", "1",
            "-disposition:v:1", "attached_pic",
        ]
    else:
        cmd += ["-map", "0:v:0", "-map", "0:a", "-map", "0:s?"]
    # -map_metadata -1: не наследуем мусорные теги исходника (например,
    # "copyright"/"title" от релизера) - ниже выставляем только своё
    cmd += [
        "-c", "copy", "-map_metadata", "-1",
        "-metadata:s:v:0", f"title={video_title}",
        "-metadata:s:v:0", f"language={video_lang}",
    ]
    cmd += stream_meta_args
    for key, value in tags.items():
        if value and key not in FFMPEG_UNSUPPORTED_KEYS:
            cmd += ["-metadata", f"{key}={value}"]
    cmd += ["-loglevel", "error", "-y", temp_file]

    try:
        # stdin=DEVNULL - иначе ffmpeg наследует stdin от tag.sh, а там
        # это тот же пайп "find | while read -r file", и ffmpeg своим
        # чтением молча ворует байты у следующей итерации read (см.
        # проверенный на реальных файлах Better Call Saul баг с
        # обрезанными путями)
        subprocess.run(cmd, check=True, stdin=subprocess.DEVNULL)
        os.replace(temp_file, file_path)
        set_unsupported_tags(file_path, tags)
        return True
    except Exception as e:
        log(f"❌ Ошибка ffmpeg: {e}")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    file_path = sys.argv[1]
    api_key = get_api_key()
    if not api_key:
        sys.exit(0)

    target = parse_target(file_path)

    try:
        if target["is_tv"]:
            log(f"🔍 Поиск в TMDB (сериал): '{target['show']}' S{target['season']:02d}E{target['episode']:02d}...")
            meta = fetch_tv_meta(target, api_key)
        else:
            year_str = f", Year: {target['year']}" if target['year'] else ", Year: None"
            log(f"🔍 Поиск в TMDB (фильм): '{target['title']}'{year_str}...")
            meta = fetch_movie_meta(target, api_key)
    except requests.RequestException as e:
        log(f"⚠️  Ошибка запроса к TMDB: {e}")
        sys.exit(0)

    tagged_ok = False
    if meta:
        poster_img = download_poster(meta.get("poster_path"))
        tagged_ok = tag_file(file_path, meta, poster_img)
        if poster_img and os.path.exists(poster_img):
            os.remove(poster_img)
    else:
        name = target.get("show") or target.get("title")
        log(f"⚠️ Не найдено: {name}")

    # Сайдкар с именем торрента удаляем только при успехе - иначе при
    # повторной попытке (например, вручную после сбоя) потеряем год и
    # страны производства без всякой пользы, раз тегирование всё равно
    # не удалось
    if tagged_ok:
        sidecar_path = file_path + ".torrentinfo.json"
        if os.path.exists(sidecar_path):
            os.remove(sidecar_path)
