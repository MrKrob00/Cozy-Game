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
- [Cube Pets](https://kenney.nl/assets/cube-pets) — кот и цыплята на выкошенных газонах;
- [Graveyard Kit](https://kenney.nl/assets/graveyard-kit) — садовая скамейка (переведена в цвет вершин тем же скриптом);
- [Fantasy Town Kit](https://kenney.nl/assets/fantasy-town-kit) — фонтан на площади.

Модели [Quaternius](https://quaternius.com), лицензия CC0:

- [Easy Enemy Pack](https://quaternius.com/packs/easyenemy.html) — лягушка.

Свои модели (`tools/make_models.py` → `assets/models/mower_*.gltf`, `straw_hat.gltf`): газонокосилка по частям (корпус трёх уровней, мотор, колёса, ручка, мешок) и соломенная шляпа. Готовой бесплатной косилки в подходящем стиле не нашлось.

Пока из примитивов: ёжик, забор, клумбы, находки.

## Звуки

Звуки [Kenney](https://kenney.nl), лицензия CC0 (`tools/import_sounds.py` → `assets/audio/*.ogg`):

- [Interface Sounds](https://kenney.nl/assets/interface-sounds) — нажатия, всплывающие окна, отказ, находка, посадка цветов;
- [Impact Sounds](https://kenney.nl/assets/impact-sounds) — штамп, удар косилки о препятствие;
- [RPG Audio](https://kenney.nl/assets/rpg-audio) — монеты, высыпание травы, калитка.

Мелодичные звуки (завершение участка, отметки прогресса, птицы, «голоса» жителей) синтезированы скриптом `tools/make_placeholder_sounds.py`. Косилка беззвучна.
