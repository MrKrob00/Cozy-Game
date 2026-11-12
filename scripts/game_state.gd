extends Node
## Глобальное состояние игры и сохранение. Автозагрузка «GameState».
##
## Ресурсы, мешок косилки, апгрейды, флаги (находки, зверьки, показанные
## подсказки) и состояние участков. Сохраняется в один файл.

signal coins_changed(value: int)
signal compost_changed(value: int)
signal bag_changed(fill: float, capacity: float)
signal upgrades_changed
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

## Настройка, а не прогресс: переживает «Начать заново».
var sound_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()


func _notification(what: int) -> void:
	# Закрытие окна, сворачивание приложения на телефоне, кнопка «назад».
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_WM_GO_BACK_REQUEST]:
		save_game()


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


func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)


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


func toast(text: String) -> void:
	toast_requested.emit(text)


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	settings_changed.emit()
	save_game()


func save_game() -> void:
	saving.emit()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить игру: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_var({
		"version": SAVE_VERSION,
		"coins": coins,
		"grass_banked": grass_banked,
		"compost_spent": compost_spent,
		"sound_enabled": sound_enabled,
		"bag_fill": bag_fill,
		"upgrade_levels": upgrade_levels,
		"flags": flags,
		"plots": plots,
	})


func load_game() -> void:
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
	grass_banked = data.get("grass_banked", 0.0)
	compost_spent = data.get("compost_spent", 0)
	sound_enabled = data.get("sound_enabled", true)
	bag_fill = data.get("bag_fill", 0.0)
	upgrade_levels = data.get("upgrade_levels", {})
	flags = data.get("flags", {})
	plots = data.get("plots", {})


## Сбрасывает прогресс в памяти, не трогая файл и сцену.
func clear() -> void:
	coins = 0
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
