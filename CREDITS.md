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

- [KayKit: Medieval Hexagon Pack](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0) — дома, кузница (мастерская), колодцы, таверна, рынок, церковь, лесопилка, мельница, ели, пни, камни, кувшинки и осока, бочки, ящики, мешки, тачка, доски;
- [KayKit: Halloween Bits](https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0) — фонарь на столбе, напольный фонарь, тыквы.

Переведены в цвет вершин скриптом `tools/convert_kaykit.py` (`assets/models/`), цвета слегка подогнаны под палитру игры.

Модели [Kenney](https://kenney.nl), лицензия CC0 (`assets/characters/`, `assets/animals/`):

- [Mini Characters](https://kenney.nl/assets/mini-characters) — герой, Мастер, Бабушка, Почтальон, со своими анимациями;
- [Cube Pets](https://kenney.nl/assets/cube-pets) — кот и цыплята на выкошенных газонах;
- [Graveyard Kit](https://kenney.nl/assets/graveyard-kit) — садовая скамейка (переведена в цвет вершин тем же скриптом);
- [Fantasy Town Kit](https://kenney.nl/assets/fantasy-town-kit) — фонтан на площади, забор участков, столбы калиток, засов мастерской;
- [Platformer Kit](https://kenney.nl/assets/platformer-kit) — указатели у калиток, замок мастерской, ключ и монеты (находки), цветы на клумбах, грибы, камни, яблоня с круглой кроной;
- [Nature Kit](https://kenney.nl/assets/nature-kit) — ветвистое дерево и дуб (листва сделана сочнее, кора — коричневой).

Модели из Fantasy Town Kit, Platformer Kit и Nature Kit — в том виде, как они скачиваются с kenney.nl (папки `fantasy-town-kit`, `platformer-kit`, `nature-kit`), переведены тем же скриптом; золото подкрашено в цвет монет игры, у цветов на клумбах три расцветки.

Модели [Quaternius](https://quaternius.com), лицензия CC0:

- [Easy Enemy Pack](https://quaternius.com/packs/easyenemy.html) — лягушка.

Свои модели (`tools/make_models.py` → `assets/models/`): газонокосилка по частям (корпус трёх уровней, мотор, колёса, ручка, мешок), соломенная шляпа, ёжик, находки (уточка, очки, садовый гном, письмо, чайник), почтовый ящик «Бюро находок», компостный ящик (сплошные стенки из досок) с кучей скошенной травы — травинки цветов травы игры, кусты, плитки дорожек, камешки, кочки травы и полевые цветы, стрелка-подсказка, яблоки, вода пруда и фонтана, струя фонтана, мох и палые листья в сухом фонтане, цветы кувшинок, бабочки, земля клумб; для эффектов — лист, слетающий с дерева (зубчики, жилки), срезанная травинка из-под косилки и комок травы, летящий в компост; для событий — воздушный шар, посылка с парашютиком, клевер-четырёхлистник, птица. Готовых бесплатных моделей в подходящем стиле для них не нашлось; кочки и цветы луга свои ещё и потому, что их на карте тысячи: у них по 30–40 треугольников.

## Звуки

Звуки [Kenney](https://kenney.nl), лицензия CC0 (`tools/import_sounds.py` → `assets/audio/*.ogg`):

- [Interface Sounds](https://kenney.nl/assets/interface-sounds) — нажатия, всплывающие окна, отказ, находка, посадка цветов;
- [Impact Sounds](https://kenney.nl/assets/impact-sounds) — штамп, удар косилки о препятствие;
- [RPG Audio](https://kenney.nl/assets/rpg-audio) — монеты, высыпание травы, калитка.

Мелодичные звуки (завершение участка, отметки прогресса, птицы, «голоса» жителей) синтезированы скриптом `tools/make_placeholder_sounds.py`. Косилка беззвучна.
