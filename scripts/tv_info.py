#!/usr/bin/env python3
import sys
import re

def clean_show_name(name):
    # 1. Заменяем точки и подчеркивания на пробелы
    name = name.replace('.', ' ').replace('_', ' ')
    
    # 2. Удаляем год (19xx или 20xx)
    name = re.sub(r'\(?(19|20)\d{2}\)?', '', name)
    
    # 3. Удаляем мусор в скобках [], ()
    name = re.sub(r'\[.*?\]', '', name)
    name = re.sub(r'\(.*?\)', '', name)

    # 4. Удаляем технический мусор
    garbage_list = [
        r'WEB-DL', r'WEBRip', r'BDRip', r'BluRay', r'HDTV', r'HDRip', r'DVDRip',
        r'AVC', r'x264', r'x265', r'h264', r'h265', r'HEVC', 
        r'AAC', r'AC3', r'MP3', r'DD5\.1',
        r'1080p', r'720p', r'480p', r'2160p', r'4K', 
        r'seleZen', r'ivanes', r'Kuglblids', r'SOFCJ', r'apreder'
    ]

    for garbage in garbage_list:
        name = re.sub(r'\b' + garbage + r'\b', '', name, flags=re.IGNORECASE)
        name = re.sub(garbage, '', name, flags=re.IGNORECASE)
    
    # 5. Финальная зачистка
    name = name.strip()
    name = re.sub(r'\s+', ' ', name)
    name = name.rstrip('.-,')
    return name

if len(sys.argv) < 2:
    sys.exit(1)

filename = sys.argv[1]

# Ищем паттерн Сезон/Эпизод
# Поддерживаем: S01E01, s1e1, S01.E01, s01_e01, 1x01 (редко, но бывает)
pattern = re.compile(r'(.*?)[\._ \-]*[Ss](\d{1,2})[\._ \-]*[Ee](\d{1,2})', re.IGNORECASE)
match = pattern.search(filename)

if match:
    raw_name = match.group(1)
    season = int(match.group(2))
    episode = int(match.group(3))
    
    clean_name = clean_show_name(raw_name)
    
    # Вывод: Name|Season|Episode
    # Пример: Last kvest|1|1
    print(f"{clean_name}|{season}|{episode}")
else:
    # Если не нашли паттерн, возвращаем пустоту или ошибку
    sys.exit(1)