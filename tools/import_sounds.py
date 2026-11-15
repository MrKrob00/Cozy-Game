#!/usr/bin/env python3
"""Берёт звуки из бесплатных наборов Kenney (CC0) и кладёт их в assets/audio
под именами игры: моно, OGG, одинаковая пиковая громкость.

Запуск из папки проекта (нужен ffmpeg):
  python3 tools/import_sounds.py <папка с наборами>

Наборы — папками рядом (годятся и зеркала на GitHub):
  interface  Kenney Interface Sounds  https://kenney.nl/assets/interface-sounds
  impact     Kenney Impact Sounds     https://kenney.nl/assets/impact-sounds
  rpg        Kenney RPG Audio         https://kenney.nl/assets/rpg-audio

Мелодичные звуки (завершение участка, птицы, «голоса» жителей) остаются
синтезированными: tools/make_placeholder_sounds.py.
"""

import os
import re
import subprocess
import sys

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
# Пиковая громкость, дБ: как у синтезированных звуков, под которые подобраны
# громкости в коде.
PEAK_DB = -9.0

# Имя звука в игре → (набор, файл[, срез высоких частот, Гц]). Варианты <имя>_1,
# <имя>_2 играют по очереди случайно. Звонкие звуки игроку мешали (pluck,
# длинный скрип калитки): вместо них глухие, верх срезан.
SOUNDS = {
    "click": ("interface", "click_002.wav"),
    "pop": ("interface", "drop_004.wav", 2400),
    "rustle_1": ("impact", "footstep_grass_000.ogg", 3000),
    "rustle_2": ("impact", "footstep_grass_001.ogg", 3000),
    "rustle_3": ("impact", "footstep_grass_002.ogg", 3000),
    "step_1": ("impact", "footstep_concrete_000.ogg", 2500),
    "step_2": ("impact", "footstep_concrete_001.ogg", 2500),
    "step_3": ("impact", "footstep_concrete_002.ogg", 2500),
    "deny": ("interface", "error_004.wav"),
    "find": ("interface", "confirmation_002.wav"),
    "plant_1": ("interface", "drop_002.wav"),
    "plant_2": ("interface", "drop_003.wav"),
    "coin_1": ("rpg", "handleCoins.ogg"),
    "coin_2": ("rpg", "handleCoins2.ogg"),
    "dump_1": ("rpg", "cloth1.ogg"),
    "dump_2": ("rpg", "cloth2.ogg"),
    "dump_3": ("rpg", "cloth3.ogg"),
    "gate": ("rpg", "creak3.ogg", 2200),
    "stamp_1": ("impact", "impact_plank_medium_000.ogg"),
    "stamp_2": ("impact", "impact_plank_medium_001.ogg"),
    "stamp_3": ("impact", "impact_plank_medium_002.ogg"),
    "bonk_1": ("impact", "impact_soft_medium_000.ogg"),
    "bonk_2": ("impact", "impact_soft_medium_001.ogg"),
    "bonk_3": ("impact", "impact_soft_medium_002.ogg"),
}


def find_file(root, file):
    for folder, _, files in os.walk(root, followlinks=True):
        if file in files:
            return os.path.join(folder, file)
    sys.exit(f"Не найден {file} в {root}")


def peak_db(path):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", out).group(1))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for name, entry in SOUNDS.items():
        file = entry[1]
        source = find_file(sys.argv[1], file)
        filters = f"lowpass=f={entry[2]}," if len(entry) > 2 else ""
        filtered = os.path.join(OUT_DIR, "_filtered.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", source, "-ac", "1", "-ar", "44100",
                        "-af", filters + "anull", filtered], check=True)
        gain = PEAK_DB - peak_db(filtered)
        target = os.path.join(OUT_DIR, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", filtered,
                        "-af", f"volume={gain:.2f}dB", "-c:a", "libvorbis", "-q:a", "4", target], check=True)
        os.remove(filtered)
        # Прежние файлы с тем же именем (синтезированные, старые варианты) больше не нужны.
        base = name.split("_")[0] if name[-1].isdigit() else name
        stale = [name + ".wav", base + ".wav"]
        if not name[-1].isdigit():
            stale += [f"{name}_{i}.ogg" for i in range(1, 6)]
        for old in stale:
            for path in (os.path.join(OUT_DIR, old), os.path.join(OUT_DIR, old + ".import")):
                if os.path.exists(path):
                    os.remove(path)
        print(f"{name}: {file} ({gain:+.1f} dB)")
