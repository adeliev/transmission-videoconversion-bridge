#!/usr/bin/env python3
"""Читает одно поле из .torrentinfo.json (см. move.sh/parse_torrent_name.py).
Печатает пустую строку и выходит с кодом 0, если файла/поля нет —
удобно для использования в bash без дополнительных проверок.
"""
import sys
import json

if len(sys.argv) < 3:
    sys.exit(0)

path, field = sys.argv[1], sys.argv[2]

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, ValueError):
    sys.exit(0)

value = data.get(field)
if value is None:
    sys.exit(0)
if isinstance(value, list):
    print(",".join(str(v) for v in value))
else:
    print(value)
