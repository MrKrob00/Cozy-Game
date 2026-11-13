class_name Village
extends Node3D
## Деревня: общий мир с улицей и участками.
##
## Определяет, на каком участке сейчас игрок, и подстраивает под него
## картинку: заросший участок блёклый и прохладный, выкошенный — яркий и тёплый.

## Игрок перешёл на другой участок (или подошёл к нему ближе, чем к остальным).
signal current_plot_changed(plot: Plot)
## Все участки выкошены: в деревне праздник. announce — показывать ли торжество
## (false при загрузке сохранения, где праздник уже был).
signal festival_started(announce: bool)

@export_group("Оживление цветом")
## Насыщенность картинки на заросшем и на выкошенном участке.
@export var saturation_range := Vector2(0.72, 1.1)
@export var sun_energy_range := Vector2(0.58, 0.74)
@export var sun_color_overgrown := Color(0.96, 0.92, 0.90)
## Золотистое солнце позднего дня — главная нота уюта.
@export var sun_color_mowed := Color(1.0, 0.88, 0.68)
@export var sky_color_overgrown := Color(0.72, 0.79, 0.82)
@export var sky_color_mowed := Color(0.66, 0.88, 0.98)

const CHIRPS := ["chirp_1", "chirp_2", "chirp_3"]
## Насколько ближе должен быть другой участок, чтобы стать текущим.
const SWITCH_MARGIN := 0.5
const FESTIVAL_FLAG := "festival"
## Свет неба (как прежний окружающий свет сцены).
## Холоднее прежнего: тень голубоватая, солнце тёплое (совет Pontus Albrecht
## и Firewatch: тёплый свет, холодная тень).
const AMBIENT := Color(0.50, 0.56, 0.74)
## Пауза между покосом последнего участка и праздником, секунд.
const FESTIVAL_DELAY := 11.0

var current_plot: Plot

var _plots: Array[Plot] = []
var _player: Node3D
var _environment: Environment
var _sun: DirectionalLight3D
## Сглаженный прогресс текущего участка, по которому меняется картинка.
var _mood := 0.0
var _chirp_timer := 3.0
var _fluff: CPUParticles3D


func _enter_tree() -> void:
	add_to_group("village")


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("plot"):
		_plots.append(node as Plot)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	for child in get_children():
		if child is WorldEnvironment:
			# Копия, чтобы не менять общий ресурс сцены. Постобработки нет:
			# насыщенность считают сами материалы (Graphics.set_day).
			_environment = child.environment.duplicate()
			_environment.adjustment_enabled = false
			child.environment = _environment
		elif child is DirectionalLight3D:
			# Солнце задаёт только направление: свет считают материалы,
			# тени рисует Shadows. Сам источник света не нужен.
			_sun = child
			_sun.visible = false
			_sun.shadow_enabled = false
			Graphics.sun_direction = Graphics.SUN_DIRECTION.normalized()
	var shadows := Shadows.new()
	shadows.name = "Shadows"
	add_child(shadows)
	var trail := GuideTrail.new()
	trail.name = "GuideTrail"
	add_child(trail)
	# Склейка деталей — когда все объекты построили свои модели.
	_bake_world.call_deferred()
	_build_fluff()
	_update_current_plot()
	_mood = current_plot.get_mood() if current_plot else 1.0
	_apply_mood()
	for plot in _plots:
		plot.completed.connect(_on_plot_completed)
	if GameState.has_flag(FESTIVAL_FLAG):
		festival_started.emit(false)


func _process(delta: float) -> void:
	if _fluff and _player:
		_fluff.global_position = _player.global_position + Vector3(0.0, 1.6, 0.0)
	_update_current_plot()
	var progress := current_plot.get_mood() if current_plot else 1.0
	if not is_equal_approx(_mood, progress):
		_mood = lerpf(_mood, progress, 1.0 - exp(-1.5 * delta))
		_apply_mood()

	# Птицы: чем больше скошено, тем чаще поют.
	_chirp_timer -= delta
	if _chirp_timer <= 0.0:
		_chirp_timer = lerpf(14.0, 3.5, progress) * randf_range(0.6, 1.4)
		if progress > 0.05:
			Sfx.play(CHIRPS.pick_random(), randf_range(-16.0, -10.0), 1.0, 0.12)


## Куда идти дальше: первый по цепочке участок, калитка которого открыта,
## а трава не выкошена. null — пока игрок занят своим участком (двор в начале
## игры, или новый участок, на котором он уже косит) и когда выкошено всё.
func next_goal() -> Plot:
	for plot in _plots:
		if plot.is_unlocked() and not plot.reveal_pending and not plot.is_completed():
			if plot.requires_plot == "":
				return null
			if current_plot == plot and plot.get_progress() > 0.0:
				return null
			return plot
	return null


func is_festival() -> bool:
	return GameState.has_flag(FESTIVAL_FLAG)


## Итоги для финального окна.
func get_summary() -> Array[String]:
	var finds := get_tree().get_nodes_in_group("find")
	var found := finds.filter(func(find: FindItem) -> bool: return find.is_collected()).size()
	var earned := 0
	var total := 0
	for plot in _plots:
		for stamp in plot.get_stamps():
			total += 1
			if stamp["earned"]:
				earned += 1
	return [
		"Участков выкошено: %d" % _plots.size(),
		"Дней в деревне: %d" % GameState.day,
		"Находок: %d из %d" % [found, finds.size()],
		"Штампов: %d из %d" % [earned, total],
	]


func _on_plot_completed() -> void:
	if is_festival():
		return
	for plot in _plots:
		if not plot.is_completed():
			return
	# Сначала игрок видит завершение последнего участка, потом начинается праздник.
	await get_tree().create_timer(FESTIVAL_DELAY).timeout
	GameState.set_flag(FESTIVAL_FLAG)
	festival_started.emit(true)
	Sfx.play("complete", 0.0, 1.12)
	Sfx.buzz(80)
	if _player:
		for i in 3:
			Juice.confetti(self, _player.global_position + Vector3(i * 1.5 - 1.5, 1.4, 0.0), 60)
	GameState.save_game()


func _update_current_plot() -> void:
	if _player == null or _plots.is_empty():
		return
	var at := _player.global_position
	var nearest: Plot = null
	var nearest_distance := INF
	for plot in _plots:
		var distance := plot.distance_to(at)
		if distance < nearest_distance:
			nearest = plot
			nearest_distance = distance
	if nearest == current_plot:
		return
	if current_plot and nearest_distance > current_plot.distance_to(at) - SWITCH_MARGIN:
		return
	current_plot = nearest
	current_plot_changed.emit(current_plot)


# Пух и пыльца в воздухе вокруг игрока: мир не застывший.
func _build_fluff() -> void:
	_fluff = CPUParticles3D.new()
	_fluff.name = "Fluff"
	_fluff.amount = 22
	_fluff.lifetime = 7.0
	_fluff.preprocess = 7.0
	_fluff.local_coords = false
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 4
	mesh.rings = 2
	_fluff.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	_fluff.material_override = material
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 1.0, 0.92, 0.0), Color(1.0, 1.0, 0.92, 0.85),
			Color(1.0, 1.0, 0.92, 0.85), Color(1.0, 1.0, 0.92, 0.0)])
	_fluff.color_ramp = fade
	_fluff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fluff.emission_box_extents = Vector3(14.0, 1.2, 10.0)
	_fluff.direction = Vector3(1.0, 0.1, -0.4)
	_fluff.spread = 30.0
	_fluff.initial_velocity_min = 0.2
	_fluff.initial_velocity_max = 0.5
	_fluff.gravity = Vector3(0.0, 0.02, 0.0)
	_fluff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fluff)


func _bake_world() -> void:
	Placeholder.bake_tree(self)


func _apply_mood() -> void:
	if _environment:
		_environment.background_color = sky_color_overgrown.lerp(sky_color_mowed, _mood)
	Graphics.set_day(sun_color_overgrown.lerp(sun_color_mowed, _mood),
			lerpf(sun_energy_range.x, sun_energy_range.y, _mood), AMBIENT,
			lerpf(saturation_range.x, saturation_range.y, _mood),
			sky_color_overgrown.lerp(sky_color_mowed, _mood))
