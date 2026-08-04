#!/usr/bin/env python3
import sys
import json
import subprocess

# Поддерживаемые языки дорожек (аудио и субтитры), порядок = приоритет
TARGET_LANGS = ["rus", "eng", "slk", "cze"]

# Варианты ISO-кодов, встречающиеся в реальных релизах, сведённые
# к канонической форме из TARGET_LANGS
LANG_ALIASES = {
    "rus": "rus", "ru": "rus",
    "eng": "eng", "en": "eng",
    "slk": "slk", "slo": "slk", "sk": "slk",
    "cze": "cze", "ces": "cze", "cs": "cze",
}

# Название дорожки после очистки (item 3): язык -> чистое имя
CANON_NAME = {
    "rus": "Russian",
    "eng": "English",
    "slk": "Slovak",
    "cze": "Czech",
}

TITLE_HINTS = {
    "rus": ["рус", "russian"],
    "eng": ["англ", "english"],
    "slk": ["словац", "slovak"],
    "cze": ["чеш", "czech"],
}


def get_file_info(file_path):
    cmd = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", "-show_format", file_path]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception:
        return None


def detect_lang(stream):
    tags = stream.get("tags", {}) or {}
    lang = (tags.get("language") or "").lower().strip()
    title = (tags.get("title") or "").lower()

    if lang in LANG_ALIASES:
        return LANG_ALIASES[lang]
    for code, hints in TITLE_HINTS.items():
        if any(h in title for h in hints):
            return code
    return None


def is_forced(stream):
    tags = stream.get("tags", {}) or {}
    title = (tags.get("title") or "").lower()
    return stream.get("disposition", {}).get("forced") == 1 or "forced" in title or "форсир" in title


def pick_audio_title(original_title, lang):
    """Уточнение item 3: если у дорожки уже есть содержательное имя
    (например студия озвучки - "Левитация", "Дубляжная", "HDRezka, MVO")
    - оставляем как есть. Меняем на каноническое имя языка только если
    исходное имя пустое или само по себе просто называет язык
    ("Русский", "Russian, AC3, 48 kHz...")."""
    title = (original_title or "").strip()
    lower = title.lower()
    if title and "русский" not in lower and "russian" not in lower:
        return title
    return CANON_NAME[lang]


def build_args(info):
    if not info or "streams" not in info:
        return []
    streams = info["streams"]

    video_idx = next(
        (i for i, s in enumerate(streams)
         if s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic")),
        None,
    )

    audio_streams = [(i, s) for i, s in enumerate(streams) if s.get("codec_type") == "audio"]
    sub_streams = [(i, s) for i, s in enumerate(streams) if s.get("codec_type") == "subtitle"]

    # --- Аудио: item 2 (только целевые языки) + item 3 (если язык не
    # определён у первой дорожки - считаем её русской) ---
    kept_audio = []
    for pos, (idx, s) in enumerate(audio_streams):
        lang = detect_lang(s)
        if lang is None and pos == 0:
            lang = "rus"
        if lang in TARGET_LANGS:
            kept_audio.append((idx, lang))

    # Если вообще ничего не распозналось (совсем нет метаданных языка)
    # берём первую дорожку и считаем её русской, а не выбрасываем всё аудио.
    if not kept_audio and audio_streams:
        idx0, _ = audio_streams[0]
        kept_audio.append((idx0, "rus"))

    # --- Субтитры: item 2, приоритет полным (full) над форсированными ---
    sub_pick = {}
    for idx, s in sub_streams:
        lang = detect_lang(s)
        if lang not in TARGET_LANGS:
            continue
        forced = is_forced(s)
        current = sub_pick.get(lang)
        if current is None or (current[1] and not forced):
            sub_pick[lang] = (idx, forced)

    # --- Формируем аргументы ffmpeg (список, НЕ одна строка через
    # пробел - имена дорожек вроде "HDRezka, MVO" или "Light Breeze"
    # содержат пробелы/запятые и сломали бы наивный word-split) ---
    args = []
    if video_idx is not None:
        args += ["-map", f"0:{video_idx}"]
    else:
        args += ["-map", "0:v:0"]

    for out_pos, (idx, lang) in enumerate(kept_audio):
        args += ["-map", f"0:{idx}"]
        args += [f"-metadata:s:a:{out_pos}", f"language={lang}"]
        original_title = (streams[idx].get("tags", {}) or {}).get("title")
        args += [f"-metadata:s:a:{out_pos}", f"title={pick_audio_title(original_title, lang)}"]

    sub_order = [lang for lang in TARGET_LANGS if lang in sub_pick]
    for out_pos, lang in enumerate(sub_order):
        idx, _ = sub_pick[lang]
        args += ["-map", f"0:{idx}"]
        args += [f"-metadata:s:s:{out_pos}", f"language={lang}"]
        args += [f"-metadata:s:s:{out_pos}", f"title={CANON_NAME[lang]}"]

    return args


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    # Один аргумент на строку (не через пробел) - см. комментарий в
    # build_args про имена дорожек с пробелами/запятыми. convert.sh
    # читает это в bash-массив через mapfile.
    for arg in build_args(get_file_info(sys.argv[1])):
        print(arg)
