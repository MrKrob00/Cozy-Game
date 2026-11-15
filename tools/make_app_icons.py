"""Значки Windows (.ico) и macOS (.icns) из assets/icons/icon.png.

Запуск из папки проекта после tools/app_art.gd: python3 tools/make_app_icons.py
"""
from PIL import Image

icon = Image.open("assets/icons/icon.png").convert("RGBA")
icon.save("assets/icons/icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
icon.save("assets/icons/icon.icns")
print("assets/icons/icon.ico, assets/icons/icon.icns")
