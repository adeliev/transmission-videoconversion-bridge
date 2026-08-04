#!/usr/bin/env python3
"""Разбирает имя торрента (формат rutracker-подобных релизов) на поля.

Пример: "Крик 7 / Scream 7 (Кевин Уильямсон / Kevin Williamson)
[2026, США, Канада, ужасы, детектив, WEB-DLRip-AVC] Dub (Продубляж) + ..."

Используется, чтобы переименовывать скачанные файлы по названию
торрента вместо мусорного имени файла-релиза.
"""
import sys
import re
import json

COUNTRIES = {
    "США", "Канада", "Великобритания", "Франция", "Германия", "Россия",
    "Испания", "Италия", "Япония", "Южная Корея", "Китай", "Австралия",
    "Бельгия", "Нидерланды", "Швеция", "Норвегия", "Дания", "Финляндия",
    "Ирландия", "Мексика", "Бразилия", "Индия", "Новая Зеландия",
}

YEAR_RE = re.compile(r'^(\d{4})(?:-(\d{4}))?$')
# "Сезон: 1", "Сезон: 1-6" (диапазон) или "Сезон: 1,2" (список)
SEASON_RE = re.compile(r'^Сезон:\s*([\d,\-\s]+)$', re.IGNORECASE)
EPISODES_RE = re.compile(r'^Серии:\s*(\d+)-(\d+)\s*из\s*(\d+)$', re.IGNORECASE)
CYRILLIC_RE = re.compile(r'[А-Яа-яЁё]')


def parse(raw_name):
    result = {
        "title_ru": None, "title_en": None,
        "seasons": [], "season_from": None, "season_to": None,
        "ep_from": None, "ep_to": None, "ep_total": None,
        "year": None, "year_to": None,
        "countries": [], "genres": [],
        "is_tv": False, "truncated": False,
    }

    # Отделяем блок в квадратных скобках [Год, Страна, Жанр... Качество]
    bracket_match = re.search(r'\[([^\]]*)\]?', raw_name)
    head = raw_name
    bracket_content = ""
    if bracket_match:
        head = raw_name[:bracket_match.start()].strip()
        bracket_content = bracket_match.group(1)
        if not raw_name[bracket_match.start():].rstrip().endswith(']'):
            result["truncated"] = True

    # Убираем хвост с режиссёрами "(...)" из head, если есть
    paren_idx = head.rfind('(')
    title_part = head[:paren_idx].strip() if paren_idx != -1 else head.strip()

    segments = [s.strip() for s in title_part.split(' / ') if s.strip()]
    title_segments = []
    for seg in segments:
        sm = SEASON_RE.match(seg)
        em = EPISODES_RE.match(seg)
        if sm:
            result["is_tv"] = True
            seasons = set()
            for part in sm.group(1).split(','):
                part = part.strip()
                if '-' in part:
                    lo, hi = part.split('-', 1)
                    seasons.update(range(int(lo), int(hi) + 1))
                elif part:
                    seasons.add(int(part))
            result["seasons"] = sorted(seasons)
            if result["seasons"]:
                result["season_from"] = result["seasons"][0]
                result["season_to"] = result["seasons"][-1]
        elif em:
            result["ep_from"] = int(em.group(1))
            result["ep_to"] = int(em.group(2))
            result["ep_total"] = int(em.group(3))
        else:
            title_segments.append(seg)

    if title_segments:
        result["title_ru"] = title_segments[0]
        # Английское название - первый НЕ-кириллический сегмент среди
        # оставшихся, а не обязательно второй по счёту: релизы часто несут
        # несколько русскоязычных вариантов названия подряд перед настоящим
        # оригинальным (например "Сексуальное просвещение / Половое
        # воспитание / Sex Education / Сезон: 1 / ..." - раньше второй
        # сегмент ошибочно принимался за title_en, а "Sex Education" вообще
        # терялся).
        for seg in title_segments[1:]:
            if not CYRILLIC_RE.search(seg):
                result["title_en"] = seg
                break

    tokens = [t.strip() for t in bracket_content.split(',') if t.strip()]
    for tok in tokens:
        ym = YEAR_RE.match(tok)
        if ym and result["year"] is None:
            result["year"] = ym.group(1)
            result["year_to"] = ym.group(2)
        elif tok in COUNTRIES:
            result["countries"].append(tok)
        else:
            result["genres"].append(tok)

    # Имя для файлов/папок: английское в приоритете, иначе русское
    result["display_title"] = result["title_en"] or result["title_ru"]

    return result


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    print(json.dumps(parse(sys.argv[1]), ensure_ascii=False))
