#!/usr/bin/env python3
import sys, re

if len(sys.argv) < 2:
    sys.exit(0)

name = sys.argv[1]

# 1. Заменяем точки и подчеркивания на пробелы
name = name.replace('.', ' ').replace('_', ' ')

# 2. Ищем год (19xx или 20xx) и отрезаем все, что после него (включая год)
match = re.search(r'\(?(19|20)\d{2}\)?', name)
if match:
    # Берем все до начала совпадения с годом
    name = name[:match.start()]

# 3. Удаляем мусор в скобках [], ()
name = re.sub(r'\[.*?\]', '', name)
name = re.sub(r'\(.*?\)', '', name)

# 4. Удаляем технический мусор (даже если он остался перед годом или года нет)
garbage_list = [
    r'WEB-DL', r'WEBRip', r'BDRip', r'BluRay', r'HDTV', r'HDRip', r'DVDRip',
    r'AVC', r'x264', r'x265', r'h264', r'h265', r'HEVC', 
    r'AAC', r'AC3', r'MP3', r'DD5\.1',
    r'1080p', r'720p', r'480p', r'2160p', r'4K', 
    r'seleZen', r'ivanes', r'Kuglblids', r'SOFCJ', r'apreder'
]

for garbage in garbage_list:
    name = re.sub(r'\b' + garbage + r'\b', '', name, flags=re.IGNORECASE)
    # Также пробуем удалять без границ слов, если это прилеплено (например 1080p)
    name = re.sub(garbage, '', name, flags=re.IGNORECASE)

# 5. Логика Языков: Eng > Ru
has_cyrillic = bool(re.search(r'[а-яА-ЯёЁ]', name))
has_latin = bool(re.search(r'[a-zA-Z]', name))

if has_cyrillic and has_latin:
    latin_match = re.search(r'([a-zA-Z].*)', name)
    if latin_match:
        potential_name = latin_match.group(1)
        name = potential_name

# 6. Финальная зачистка
name = name.strip()
name = re.sub(r'\s+', ' ', name)
name = name.rstrip('.-,')

print(name)