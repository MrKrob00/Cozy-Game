extends Node
## Глобальное состояние игры и сохранение. Автозагрузка «GameState».
##
## Ресурсы, мешок косилки, апгрейды, флаги (находки, зверьки, показанные
## подсказки) и состояние участков. Сохраняется в один файл.

signal coins_changed(value: int)
signal compost_changed(value: int)
signal bag_changed(fill: float, capacity: float)
signal upgrades_changed
## Игрок проспал ночь: наступил новый день.
signal day_started(day: int)
## Награда появилась в мире: интерфейс покажет, как она летит к счётчику.
## kind — «coins» или «compost».
signal reward_shown(kind: String, amount: int, world_position: Vector3)
## Короткое сообщение игроку; показывает интерфейс.
signal toast_requested(text: String)
## Перед записью файла: участки складывают своё состояние в plots.
signal saving
signal settings_changed

const SAVE_PATH := "user://save.dat"
const SAVE_VERSION := 1
## Сколько единиц травы даёт один компост.
const GRASS_PER_COMPOST := 10.0

## Апгрейды косилки: значения по уровням и цены перехода на следующий уровень.
const UPGRADES := {
	"blade": {
		"title": "Нож",
		"about": "Ширина покоса",
		"unit": "м",
		"values": [0.6, 0.8, 1.0],
		"costs": [60, 220],
	},
	"bag": {
		"title": "Мешок",
		"about": "Вместимость",
		"unit": "ед.",
		"values": [60.0, 100.0, 150.0],
		"costs": [50, 200],
	},
	"motor": {
		"title": "Мотор",
		"about": "Скорость",
		"unit": "м/с",
		"values": [2.5, 3.0, 3.5],
		"costs": [60, 240],
	},
}

var coins := 0
var day := 1
## Вся трава, отвезённая в компост, в единицах мешка.
var grass_banked := 0.0
## Сколько компоста уже потрачено (на клумбы и т. п.).
var compost_spent := 0
var bag_fill := 0.0
## Уровни апгрейдов, считая с нуля.
var upgrade_levels: Dictionary = {}
## Произвольные отметки: «find_key», «animal_hedgehog» и т. п.
var flags: Dictionary = {}
## Состояние участков по идентификатору.
var plots: Dictionary = {}

var compost: int:
	get:
		return int(grass_banked / GRASS_PER_COMPOST) - compost_spent

var bag_capacity: float:
	get:
		return upgrade_value("bag")

# Настройки, а не прогресс: переживают «Начать заново».
var sound_enabled := true
## Титульный экран уже показан в этом запуске (после «Начать заново» его нет).
var title_seen := false
var music_enabled := true
## Качество графики: 0 — низкое, 1 — среднее, 2 — высокое, -1 — выбрать по устройству.
var graphics_quality := -1
var show_fps := false
## Сенсорное управление: 0 — джойстик закреплён слева внизу, 1 — джойстик
## появляется под пальцем и идёт за ним, 2 — косилка едет к пальцу.
var touch_controls := 0
## Язык: «ru», «en» или пусто — выбрать по языку устройства.
var language := ""
## Прежнее название игры (и её папки с сохранением на компьютере).
const OLD_NAME := "Cozy Game"
const LANGUAGES := {"ru": "Русский", "en": "English"}
## Языки устройства, при которых игра стартует на русском.
const RUSSIAN_LOCALES := ["ru", "uk", "be", "kk"]
const TOUCH_CONTROLS := ["джойстик слева", "джойстик под пальцем", "вести пальцем"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Английский перевод; русские строки — исходные, им перевод не нужен.
	var english := Translation.new()
	english.locale = "en"
	for source: String in StringsEn.MESSAGES:
		english.add_message(source, StringsEn.MESSAGES[source])
	TranslationServer.add_translation(english)
	load_game()
	apply_language()


func _notification(what: int) -> void:
	# Закрытие окна, сворачивание приложения на телефоне, кнопка «назад».
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_WM_GO_BACK_REQUEST]:
		save_game()


## Есть ли что продолжать: на титульном экране «Продолжить» вместо «Играть».
func has_progress() -> bool:
	if grass_banked > 0.0 or bag_fill > 0.0 or coins > 0 or not flags.is_empty():
		return true
	# Записи участков есть всегда; прогресс — это отметки и завершение.
	for state: Dictionary in plots.values():
		if state.has("milestones") or state.get("completed", false):
			return true
	return false


func is_bag_full() -> bool:
	return bag_fill >= bag_capacity - 0.001


## Кладёт срезанную траву в мешок.
func add_grass(units: float) -> void:
	var was_full := is_bag_full()
	bag_fill = minf(bag_fill + units, bag_capacity)
	bag_changed.emit(bag_fill, bag_capacity)
	if is_bag_full() and not was_full:
		toast("Мешок полон — отвезите траву в компостный ящик")


## Высыпает мешок в компост. Возвращает, сколько компоста прибавилось.
func empty_bag() -> int:
	var before := compost
	grass_banked += bag_fill
	bag_fill = 0.0
	bag_changed.emit(bag_fill, bag_capacity)
	compost_changed.emit(compost)
	return compost - before


## Тратит компост. Возвращает false и ничего не меняет, если его не хватает.
func spend_compost(amount: int) -> bool:
	if compost < amount:
		return false
	compost_spent += amount
	compost_changed.emit(compost)
	return true


## Добавляет монеты. Если указано место в мире, монетки летят оттуда к счётчику.
func add_coins(amount: int, from: Variant = null) -> void:
	coins += amount
	if from is Vector3:
		reward_shown.emit("coins", amount, from)
	coins_changed.emit(coins)


## Показать, как награда летит из точки мира к счётчику (сама награда уже начислена).
func show_reward(kind: String, amount: int, at: Vector3) -> void:
	reward_shown.emit(kind, amount, at)


## Тратит монеты. Возвращает false и ничего не меняет, если их не хватает.
func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true


## Наступает следующий день: на выкошенных участках отрастает трава.
func next_day() -> void:
	day += 1
	day_started.emit(day)
	save_game()


func upgrade_level(id: String) -> int:
	return upgrade_levels.get(id, 0)


## Текущее значение апгрейда (ширина ножа, вместимость мешка, скорость).
func upgrade_value(id: String) -> float:
	return UPGRADES[id]["values"][upgrade_level(id)]


func is_upgrade_maxed(id: String) -> bool:
	return upgrade_level(id) >= UPGRADES[id]["costs"].size()


## Цена следующего уровня; -1, если апгрейд на максимуме.
func upgrade_cost(id: String) -> int:
	if is_upgrade_maxed(id):
		return -1
	return UPGRADES[id]["costs"][upgrade_level(id)]


## Покупает следующий уровень. Возвращает false, если не хватает монет или уровень последний.
func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or coins < cost:
		return false
	coins -= cost
	upgrade_levels[id] = upgrade_level(id) + 1
	coins_changed.emit(coins)
	upgrades_changed.emit()
	bag_changed.emit(bag_fill, bag_capacity)
	save_game()
	return true


func has_flag(key: String) -> bool:
	return flags.has(key)


func set_flag(key: String) -> void:
	flags[key] = true


## Словарь состояния участка; создаётся при первом обращении.
func plot_state(plot_id: String) -> Dictionary:
	if not plots.has(plot_id):
		plots[plot_id] = {}
	return plots[plot_id]


func is_plot_completed(plot_id: String) -> bool:
	return plots.has(plot_id) and plots[plot_id].get("completed", false)


## Открыл ли участок дорогу на следующий: для этого хватает выкосить его
## большую часть (Plot.open_next_at), не дожидаясь завершения.
func has_plot_opened_next(plot_id: String) -> bool:
	return plots.has(plot_id) and (plots[plot_id].get("next_opened", false) or plots[plot_id].get("completed", false))


func toast(text: String) -> void:
	# Целые сообщения переводятся здесь; с подстановкой — до неё (L.t).
	toast_requested.emit(L.t(text))


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	settings_changed.emit()
	save_game()


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	settings_changed.emit()
	save_game()


## Действующее качество графики: на телефоне и в браузере по умолчанию низкое.
func get_quality() -> int:
	if graphics_quality >= 0:
		return clampi(graphics_quality, 0, 2)
	return 0 if OS.has_feature("mobile") or OS.has_feature("web") else 2


func set_graphics_quality(quality: int) -> void:
	graphics_quality = clampi(quality, 0, 2)
	settings_changed.emit()
	save_game()


func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	settings_changed.emit()
	save_game()


## Действующий язык: выбранный игроком или язык устройства.
func get_language() -> String:
	if LANGUAGES.has(language):
		return language
	return "ru" if OS.get_locale_language() in RUSSIAN_LOCALES else "en"


## Меняет язык. Уже показанные тексты обновятся после перезагрузки сцены
## (её делает интерфейс).
func set_language(code: String) -> void:
	language = code
	apply_language()
	settings_changed.emit()
	save_game()


func apply_language() -> void:
	TranslationServer.set_locale(get_language())


func set_touch_controls(scheme: int) -> void:
	touch_controls = posmod(scheme, TOUCH_CONTROLS.size())
	settings_changed.emit()
	save_game()


func save_game() -> void:
	# При запекании карты (tools/bake_map.gd) сохранение игрока не трогаем.
	if MapBake.is_baking():
		return
	saving.emit()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить игру: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_var({
		"version": SAVE_VERSION,
		"coins": coins,
		"day": day,
		"grass_banked": grass_banked,
		"compost_spent": compost_spent,
		"sound_enabled": sound_enabled,
		"music_enabled": music_enabled,
		"graphics_quality": graphics_quality,
		"show_fps": show_fps,
		"touch_controls": touch_controls,
		"language": language,
		"bag_fill": bag_fill,
		"upgrade_levels": upgrade_levels,
		"flags": flags,
		"plots": plots,
	})


# Игра раньше называлась «Cozy Game», и на компьютере её сохранение лежит
# в папке с этим именем: при первом запуске под новым именем забираем его.
func _adopt_old_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		return
	var old := OS.get_user_data_dir().get_base_dir().path_join(OLD_NAME).path_join(SAVE_PATH.get_file())
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(SAVE_PATH))


func load_game() -> void:
	_adopt_old_save()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = file.get_var()
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		push_warning("Сохранение от другой версии игры, начинаем заново")
		return
	coins = data.get("coins", 0)
	day = data.get("day", 1)
	grass_banked = data.get("grass_banked", 0.0)
	compost_spent = data.get("compost_spent", 0)
	sound_enabled = data.get("sound_enabled", true)
	music_enabled = data.get("music_enabled", true)
	graphics_quality = data.get("graphics_quality", -1)
	show_fps = data.get("show_fps", false)
	touch_controls = clampi(data.get("touch_controls", 0), 0, TOUCH_CONTROLS.size() - 1)
	language = data.get("language", "")
	bag_fill = data.get("bag_fill", 0.0)
	upgrade_levels = data.get("upgrade_levels", {})
	flags = data.get("flags", {})
	plots = data.get("plots", {})


## Сбрасывает прогресс в памяти, не трогая файл и сцену.
func clear() -> void:
	coins = 0
	day = 1
	grass_banked = 0.0
	compost_spent = 0
	bag_fill = 0.0
	upgrade_levels = {}
	flags = {}
	plots = {}


## Стирает прогресс и запускает игру с начала.
func reset_game() -> void:
	clear()
	# Файл перезаписываем, а не удаляем: в нём остаются настройки.
	save_game()
	get_tree().paused = false
	get_tree().reload_current_scene()
