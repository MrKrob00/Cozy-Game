#!/bin/sh
# Снимает трейлер (tools/trailer.gd) и собирает его в docs/trailer.mp4.
# Нужны: Godot 4.8 (переменная GODOT или команда godot), ffmpeg и экран
# (на сервере без экрана — запускать через xvfb-run).
# Запуск из папки проекта: tools/make_trailer.sh
set -e
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
# Кадры пишутся в размере проекта (1920×1080), ролик сжимается до 1280×720.
"$GODOT" --path . --rendering-driver opengl3 --fixed-fps 30 \
	--write-movie "$OUT/f.png" --script tools/trailer.gd > "$OUT/log.txt" 2>&1
START=$(grep TRAILER_START "$OUT/log.txt" | awk '{print $2}')
END=$(grep TRAILER_END "$OUT/log.txt" | awk '{print $2}')
SECONDS_FROM=$(awk "BEGIN {print $START / 30}")
LENGTH=$(awk "BEGIN {print ($END - $START) / 30}")
FADE=$(awk "BEGIN {print ($END - $START) / 30 - 0.6}")
ffmpeg -y -loglevel error -framerate 30 -i "$OUT/f%08d.png" -i "$OUT/f.wav" \
	-ss "$SECONDS_FROM" -t "$LENGTH" \
	-vf "scale=1280:-2:flags=lanczos,fade=t=in:st=$SECONDS_FROM:d=0.25,fade=t=out:st=$(awk "BEGIN {print $SECONDS_FROM + $FADE}"):d=0.6" \
	-af "volume=-2dB,afade=t=in:st=$SECONDS_FROM:d=0.3,afade=t=out:st=$(awk "BEGIN {print $SECONDS_FROM + $FADE}"):d=0.6" \
	-c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart docs/trailer.mp4
echo "docs/trailer.mp4: $LENGTH с"
rm -rf "$OUT"
