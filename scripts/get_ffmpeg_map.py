#!/usr/bin/env python3
import sys
import json
import subprocess

def get_file_info(file_path):
    cmd = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", "-show_format", file_path]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception: return None

def find_tracks(info):
    if not info or "streams" not in info: return ""
    mapping = ["-map 0:v:0"]
    audio_tracks = []
    sub_selection = {"rus": {"full": None, "forced": None}, "eng": {"full": None, "forced": None}}
    target_langs = ["rus", "eng", "und", "zxx"]
    target_names = ["russian", "english", "original", "оригина", "русск", "англ"]
    for i, stream in enumerate(info["streams"]):
        s_type = stream.get("codec_type")
        tags = stream.get("tags", {}) or {}
        lang = tags.get("language", "").lower()
        title = tags.get("title", "").lower()
        is_target = any(l in lang for l in target_langs) or any(n in title for n in target_names)
        if s_type == "audio":
            if is_target: audio_tracks.append(i)
        elif s_type == "subtitle":
            codec = stream.get("codec_name", "").lower()
            if codec in ["subrip", "ass", "ssa", "mov_text", "text"]:
                s_lang = "rus" if ("rus" in lang or "рус" in title) else "eng" if ("eng" in lang or "англ" in title) else None
                if s_lang:
                    is_forced = stream.get("disposition", {}).get("forced") == 1 or "forced" in title or "форсир" in title
                    ptype = "forced" if is_forced else "full"
                    if sub_selection[s_lang][ptype] is None: sub_selection[s_lang][ptype] = i
    if not audio_tracks:
        audio_tracks = [i for i, s in enumerate(info["streams"]) if s.get("codec_type") == "audio"]
    for idx in audio_tracks: mapping.append(f"-map 0:{idx}")
    for l in ["rus", "eng"]:
        idx = sub_selection[l]["full"] if sub_selection[l]["full"] is not None else sub_selection[l]["forced"]
        if idx is not None: mapping.append(f"-map 0:{idx}")
    return " ".join(mapping)

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(1)
    res = find_tracks(get_file_info(sys.argv[1]))
    if res: print(res)
