#!/usr/bin/env python3
"""Определяет новые имена файлов для серий сериала внутри ОДНОГО
торрента, когда move.sh не может положиться на явные паттерны в именах
файлов (см. tv_info.py: sXXeYY, "NN сер.") - только "счётчик" где-то в
имени, например "1.Отель Элеон 2016.WEB-DL.(720p).mkv" ... "21...mkv".

Идея: токенизируем все имена файлов на чередующиеся (текст, число)
кусочки. Если структура (число и порядок кусочков) одинакова для всех
файлов, и ровно ОДНА позиция-число отличается между файлами (все
остальные, включая текст и другие числа вроде года/разрешения,
совпадают) - это и есть номер серии. Сезон берём из имени торрента
(сайдкар), только когда он однозначен (season_from == season_to).

Использование: сайдкар (JSON, как из parse_torrent_name.py) подаётся
через stdin, пути к видеофайлам - аргументами командной строки.

Печатает по одной строке на КАЖДЫЙ входной файл, в том же порядке:
    <путь>|<новое имя без расширения>   - если удалось определить
    <путь>|                             - если нет (использовать как есть)
"""
import sys
import os
import re
import json

TOKEN_RE = re.compile(r'(\d+)')


def tokenize(name):
    return TOKEN_RE.split(name)


def detect_episode_numbers(paths):
    if len(paths) < 2:
        return None

    names = [os.path.splitext(os.path.basename(p))[0] for p in paths]
    tokenized = [tokenize(n) for n in names]

    length = len(tokenized[0])
    if any(len(t) != length for t in tokenized):
        return None  # разная структура имён - не наш случай

    varying = [i for i in range(length) if len({t[i] for t in tokenized}) > 1]
    if len(varying) != 1:
        return None  # должна отличаться ровно одна позиция

    pos = varying[0]
    if pos % 2 == 0:
        return None  # чётный индекс - это текст, а не число

    try:
        episodes = [int(t[pos]) for t in tokenized]
    except ValueError:
        return None

    if len(set(episodes)) != len(episodes):
        return None  # повторяющиеся номера - что-то не так

    return episodes


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit(1)

    def emit_empty():
        for p in paths:
            print(f"{p}|")

    try:
        sidecar = json.loads(sys.stdin.read())
    except ValueError:
        sidecar = {}

    if not sidecar.get("is_tv"):
        emit_empty()
        return

    season_from = sidecar.get("season_from")
    season_to = sidecar.get("season_to")
    if season_from is None or season_from != season_to:
        emit_empty()
        return

    show_name = sidecar.get("display_title")
    if not show_name:
        emit_empty()
        return

    episodes = detect_episode_numbers(paths)
    if episodes is None:
        emit_empty()
        return

    season = int(season_from)
    for path, ep in zip(paths, episodes):
        new_base = f"{show_name} - s{season:02d}e{ep:02d}"
        print(f"{path}|{new_base}")


if __name__ == "__main__":
    main()
