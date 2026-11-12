extends Node
## Настройки графики. Автозагрузка «Graphics».
##
## Три набора качества. Главные рычаги производительности на телефоне —
## плотность травы, разрешение 3D-картинки и тени.

## Набор качества сменился: поля травы перестраиваются.
signal quality_changed

const PRESETS := [
	{
		"title": "низкая",
		# Доля от полной плотности травы; травинки шире, чтобы газон не выглядел редким.
		"grass_density": 0.4,
		"blade_width": 1.5,
		# Масштаб разрешения 3D (интерфейс всегда в полном разрешении).
		"render_scale": 0.7,
		"msaa": false,
		"shadow_size": 1024,
		"soft_shadows": false,
		# Тени на траве — самая дорогая часть: каждая травинка читает карту теней.
		"grass_shadows": false,
		"shadow_distance": 32.0,
	},
	{
		"title": "средняя",
		"grass_density": 0.65,
		"blade_width": 1.25,
		"render_scale": 0.85,
		"msaa": false,
		"shadow_size": 2048,
		"soft_shadows": true,
		"grass_shadows": true,
		"shadow_distance": 45.0,
	},
	{
		"title": "высокая",
		"grass_density": 1.0,
		"blade_width": 1.0,
		"render_scale": 1.0,
		"msaa": true,
		"shadow_size": 4096,
		"soft_shadows": true,
		"grass_shadows": true,
		"shadow_distance": 70.0,
	},
]

const GRASS_SHADER := preload("res://shaders/grass.gdshader")

var preset: Dictionary:
	get:
		return PRESETS[GameState.get_quality()]

var _applied_quality := -1
var _grass_shader_flat: Shader


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.settings_changed.connect(_apply)
	_apply()


## Шейдер травы для текущего качества: обычный или без теней.
func grass_shader() -> Shader:
	if preset["grass_shadows"]:
		return GRASS_SHADER
	if _grass_shader_flat == null:
		_grass_shader_flat = Shader.new()
		_grass_shader_flat.code = GRASS_SHADER.code.replace(
				"render_mode cull_disabled, world_vertex_coords;",
				"render_mode cull_disabled, world_vertex_coords, shadows_disabled;")
	return _grass_shader_flat


func _apply() -> void:
	var settings := preset
	var view := get_tree().root
	view.scaling_3d_scale = settings["render_scale"]
	view.msaa_3d = Viewport.MSAA_2X if settings["msaa"] else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(settings["shadow_size"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_LOW if settings["soft_shadows"]
			else RenderingServer.SHADOW_QUALITY_HARD)
	var quality := GameState.get_quality()
	if quality != _applied_quality:
		_applied_quality = quality
		quality_changed.emit()
