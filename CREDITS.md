# Авторы и лицензии

## Музыка

Kevin MacLeod ([incompetech.com](https://incompetech.com)), лицензия [Creative Commons: By Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

| Трек | Файл |
|---|---|
| Wholesome | `assets/music/wholesome.ogg` |
| Easy Lemon | `assets/music/easy_lemon.ogg` |
| Pleasant Porridge | `assets/music/pleasant_porridge.ogg` |
| Carefree | `assets/music/carefree.ogg` |

Треки перекодированы в OGG Vorbis 80 кбит/с с выравниванием громкости; сама музыка не изменялась. В игре автор указан в меню паузы.

## 3D-модели

Модели Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)), лицензия CC0:

- [KayKit: Medieval Hexagon Pack](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0) — дома, кузница (мастерская), колодцы, таверна, рынок, церковь, лесопилка, мельница, деревья, пни, камни, кувшинки и осока, бочки, ящики, мешки, тачка, доски;
- [KayKit: Halloween Bits](https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0) — фонарь на столбе, напольный фонарь, тыквы.

Переведены в цвет вершин скриптом `tools/convert_kaykit.py` (`assets/models/`), цвета слегка подогнаны под палитру игры.

Модели [Kenney](https://kenney.nl), лицензия CC0 (`assets/characters/`, `assets/animals/`):

- [Mini Characters](https://kenney.nl/assets/mini-characters) — герой, Мастер, Бабушка, Почтальон, со своими анимациями;
- [Cube Pets](https://kenney.nl/assets/cube-pets) — кот.

Модели [Quaternius](https://quaternius.com), лицензия CC0:

- [Easy Enemy Pack](https://quaternius.com/packs/easyenemy.html) — лягушка.

Свои модели (`tools/make_models.py` → `assets/models/mower_*.gltf`, `straw_hat.gltf`): газонокосилка по частям (корпус трёх уровней, мотор, колёса, ручка, мешок) и соломенная шляпа. Готовой бесплатной косилки в подходящем стиле не нашлось.

Пока из примитивов: ёжик, забор, скамейки, клумбы, фонтан, находки.

## Звуки

Временные, синтезированы скриптом `tools/make_placeholder_sounds.py` для этого проекта.
