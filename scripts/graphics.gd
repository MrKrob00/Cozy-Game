extends Node
## Графика: наборы качества, свет дня и тени предметов. Автозагрузка «Graphics».
##
## Источники света Godot не используются: все материалы игры «unshaded»
## и считают свет сами по параметрам, которые ставит этот узел (см.
## shaders/day.gdshaderinc). Тени предметов — картинка сверху от Shadows
## (shaders/shade.gdshaderinc). Так нет ни карты теней, ни прохода света,
## ни постобработки.

## Набор качества сменился: поля травы перестраиваются.
signal quality_changed
## Появились новые модели, отбрасывающие тень (Placeholder.bake).
signal casters_changed

const PRESETS := [
	{
		"title": "низкая",
		# Доля от полной плотности травы; травинки шире, чтобы газон не выглядел редким.
		"grass_density": 0.4,
		"blade_width": 1.6,
		# Травинок в пучке.
		"blades": 2,
		# Скошенный пучок: 0 — не рисуется совсем, газон рисует земля.
		"stubble": 0.0,
		# Масштаб разрешения 3D (интерфейс всегда в полном разрешении).
		"render_scale": 0.75,
		"msaa": false,
		# Картинка теней: сторона в пикселях.
		"shade_size": 512,
		# Доля россыпей луга (кочки, цветы).
		"scatter": 0.5,
	},
	{
		"title": "средняя",
		"grass_density": 0.65,
		"blade_width": 1.25,
		"blades": 3,
		"stubble": 0.1,
		"render_scale": 0.9,
		"msaa": false,
		"shade_size": 1024,
		"scatter": 0.75,
	},
	{
		"title": "высокая",
		"grass_density": 1.0,
		"blade_width": 1.0,
		"blades": 3,
		"stubble": 0.1,
		"render_scale": 1.0,
		"msaa": true,
		"shade_size": 1024,
		"scatter": 1.0,
	},
]

## Общая яркость света дня. Подобрана по снимкам: без неё в Compatibility
## выкошенный газон светлее, чем был в Mobile, и упирается в белый.
const EXPOSURE := 0.86
const BOUNCE := Color(0.50, 0.44, 0.30)
const GLOW := Color(0.36, 0.14, 0.03)
## Направление солнечных лучей. Солнце светит из-за плеча камеры, слева:
## к игроку обращены освещённые стороны предметов, тени падают от камеры.
## (Раньше свет шёл сбоку-сзади, и деревья с кустами были к нам теневой стороной.)
const SUN_DIRECTION := Vector3(-0.28, -0.76, -0.58)

var preset: Dictionary:
	get:
		return PRESETS[GameState.get_quality()]

var sun_direction := SUN_DIRECTION.normalized()

var _applied_quality := -1
# Материалы, которым нужен свет дня; отдельно — те, что принимают тени.
var _lit: Array[ShaderMaterial] = []
var _receivers: Array[ShaderMaterial] = []
var _day := {
	"day_dir": SUN_DIRECTION.normalized(),
	"day_sun": Vector3(0.7, 0.672, 0.602),
	"day_ambient": Vector3(0.546, 0.588, 0.665),
	"day_bounce": Vector3(0.43, 0.40, 0.28),
	"day_glow": Vector3(0.26, 0.10, 0.02),
	"day_saturation": 1.0,
	"haze_color": Vector3(0.39, 0.74, 0.96),
}
var _shade := {
	"shade_tex": null,
	"shade_rect": Vector4.ZERO,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.settings_changed.connect(_apply)
	_apply()


## Подключает материал к свету дня (и к теням предметов, если receives).
func track(material: ShaderMaterial, receives := false) -> ShaderMaterial:
	if material in _lit:
		return material
	_lit.append(material)
	for key: String in _day:
		material.set_shader_parameter(key, _day[key])
	if receives:
		_receivers.append(material)
		for key: String in _shade:
			material.set_shader_parameter(key, _shade[key])
	return material


## Свет дня: цвет солнца с яркостью, свет неба, насыщенность картинки
## и цвет дымки (обычно цвет неба).
func set_day(sun: Color, sun_energy: float, ambient: Color, saturation: float,
		haze := Color(0.66, 0.88, 0.98)) -> void:
	var haze_linear := haze.srgb_to_linear()
	_day["haze_color"] = Vector3(haze_linear.r, haze_linear.g, haze_linear.b)
	# Меньше заполняющего света и больше солнца: формы читаются, картинка
	# не плоская.
	_day["day_sun"] = Vector3(sun.r, sun.g, sun.b) * sun_energy * EXPOSURE * 1.3
	_day["day_ambient"] = Vector3(ambient.r, ambient.g, ambient.b) * EXPOSURE * 0.72
	# Отражённый от земли свет — тёплый, от него тени снизу не серые.
	_day["day_bounce"] = Vector3(BOUNCE.r, BOUNCE.g, BOUNCE.b) * EXPOSURE * 0.72
	_day["day_glow"] = Vector3(GLOW.r, GLOW.g, GLOW.b) * sun_energy
	_day["day_saturation"] = saturation
	_push(_lit, _day)


## Картинка теней и её окно (вызывает Shadows).
func set_shade(texture: Texture2D, rect: Vector4) -> void:
	_shade["shade_tex"] = texture
	_shade["shade_rect"] = rect
	_push(_receivers, _shade)


func _push(materials: Array[ShaderMaterial], values: Dictionary) -> void:
	for material in materials:
		for key: String in values:
			material.set_shader_parameter(key, values[key])


func _apply() -> void:
	var settings := preset
	var view := get_tree().root
	view.scaling_3d_scale = settings["render_scale"]
	view.msaa_3d = Viewport.MSAA_2X if settings["msaa"] else Viewport.MSAA_DISABLED
	var quality := GameState.get_quality()
	if quality != _applied_quality:
		_applied_quality = quality
		quality_changed.emit()
