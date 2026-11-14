class_name MapBake
## Запечённое окружение деревни: земля, дороги, дома, деревья, россыпи луга.
##
## Всё это строится по правилам (Terrain, Meadow, village_decor), но не при
## запуске игры, а заранее: `tools/bake_map.gd` сохраняет готовые модели
## в scenes/baked/, игра их только загружает. После правки карты или её
## правил запекание надо повторить — за этим следит проверка в tests/village.gd:
##   godot --headless --path . --script tools/bake_map.gd

const DIRECTORY := "res://scenes/baked/"
## Земля, дороги, постройки, деревья — одни на все наборы графики.
const BASE := DIRECTORY + "decor.scn"
## Россыпи луга (кочки, цветы, камни): по файлу на набор графики.
const SCATTER := DIRECTORY + "scatter_%d.scn"
## От чего зависит запечённое: изменился любой из файлов — пора перепекать.
const SOURCES := [
	"res://scripts/terrain.gd", "res://scripts/village_decor.gd", "res://scripts/meadow.gd",
	"res://scripts/placeholder.gd", "res://scripts/plot_prop.gd", "res://scripts/plot_fence.gd",
	"res://scripts/models.gd", "res://scripts/map_bake.gd", "res://scenes/village.tscn",
	"res://tools/bake_map.gd",
]


## Запекание идёт прямо сейчас (окружение строится по правилам, сохранения выключены).
static func is_baking() -> bool:
	return Engine.has_meta("baking_map")


## Есть ли запечённое окружение.
static func is_available() -> bool:
	return not is_baking() and ResourceLoader.exists(BASE)


## Отпечаток всего, от чего зависит запечённое. Работает только там, где
## исходники лежат текстом (редактор, проверки), в собранной игре не нужен.
static func source_key() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in SOURCES:
		context.update(FileAccess.get_file_as_bytes(path))
	var models := DirAccess.get_files_at("res://assets/models")
	models.sort()
	for file in models:
		if file.ends_with(".gltf"):
			context.update(FileAccess.get_file_as_bytes("res://assets/models/" + file))
	return context.finish().hex_encode().substr(0, 16)
