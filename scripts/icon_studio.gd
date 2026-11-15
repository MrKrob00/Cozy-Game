class_name IconStudio
extends Node
## Значки интерфейса, снятые с настоящих моделей игры: кочка травы (участок),
## мешок косилки, компостный ящик с травой, мотор. Каждая картинка снимается
## один раз за запуск в своей маленькой сцене (свой мир, прозрачный фон) и
## дальше только показывается (HudIcon).

const SIZE := 192
## Сколько кадров снимать, прежде чем выключить съёмку.
const FRAMES := 6
## Что снимать: модели (имя, где стоит, масштаб) и откуда смотреть.
const SETS := {
	"grass": [["tuft_2", Vector3.ZERO, Vector3.ONE * 1.1], ["tuft_1", Vector3(0.14, 0.0, 0.08), Vector3.ONE * 0.9],
			["tuft_0", Vector3(-0.13, 0.0, 0.1), Vector3.ONE * 0.85]],
	"bag": [["mower_bag", Vector3.ZERO, Vector3.ONE]],
	"compost": [["compost_bin", Vector3.ZERO, Vector3.ONE],
			["compost_pile", Vector3(0.0, 0.3, 0.0), Vector3(1.0, 1.5, 0.85)]],
	"motor": [["mower_engine", Vector3.ZERO, Vector3.ONE], ["mower_cap", Vector3.ZERO, Vector3.ONE]],
}
## Откуда смотрит камера: сверху-сбоку, как камера игры; траву — ниже,
## сбоку: сверху тонкие травинки сливаются.
const VIEW := Vector3(0.55, 0.8, 1.0)
const VIEWS := {"grass": Vector3(0.25, 0.3, 1.0)}

static var _studio: IconStudio
static var _textures: Dictionary = {}


## Картинка набора name (снимается при первом запросе; в первом кадре ещё пустая).
static func texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	if not SETS.has(name) or DisplayServer.get_name() == "headless":
		return null
	if _studio == null or not is_instance_valid(_studio):
		_studio = IconStudio.new()
		_studio.name = "IconStudio"
		_studio.process_mode = Node.PROCESS_MODE_ALWAYS
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_studio)
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	# Несколько кадров подряд, потом съёмка выключается (картинка остаётся):
	# снятая в первом же кадре сцены выходила пустой или не с той точки.
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.set_meta("frames_left", FRAMES)
	_studio.add_child(view)
	_studio.set_process(true)
	var stage := Node3D.new()
	view.add_child(stage)
	var box := AABB()
	var first := true
	for part: Array in SETS[name]:
		var model := Models.place(stage, part[0], part[1], 1.0, 0.0, false)
		model.scale = part[2]
		var bounds: AABB = model.transform * Models.mesh(part[0]).get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	var camera := Camera3D.new()
	camera.fov = 28.0
	view.add_child(camera)
	var center := box.get_center()
	var radius := box.size.length() * 0.5
	var distance := radius / sin(deg_to_rad(camera.fov * 0.5)) * 0.86
	var eye := center + (VIEWS.get(name, VIEW) as Vector3).normalized() * distance
	camera.transform = Transform3D(Basis.looking_at(center - eye, Vector3.UP), eye)
	_textures[name] = view.get_texture()
	return _textures[name]


func _process(_delta: float) -> void:
	var busy := false
	for view: SubViewport in get_children():
		var left: int = view.get_meta("frames_left", 0)
		if left <= 0:
			continue
		left -= 1
		view.set_meta("frames_left", left)
		if left == 0:
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		else:
			busy = true
	if not busy:
		set_process(false)
