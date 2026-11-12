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
@export var sun_color_overgrown := Color(0.9, 0.93, 1.0)
@export var sun_color_mowed := Color(1.0, 0.95, 0.84)
@export var sky_color_overgrown := Color(0.72, 0.79, 0.82)
@export var sky_color_mowed := Color(0.66, 0.88, 0.98)

const CHIRPS := ["chirp_1", "chirp_2", "chirp_3"]
## Насколько ближе должен быть другой участок, чтобы стать текущим.
const SWITCH_MARGIN := 0.5
const FESTIVAL_FLAG := "festival"
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


func _enter_tree() -> void:
	add_to_group("village")


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("plot"):
		_plots.append(node as Plot)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	for child in get_children():
		if child is WorldEnvironment:
			# Копия, чтобы не менять общий ресурс сцены.
			_environment = child.environment.duplicate()
			_environment.adjustment_enabled = true
			child.environment = _environment
		elif child is DirectionalLight3D:
			_sun = child
	_update_current_plot()
	_mood = current_plot.get_mood() if current_plot else 1.0
	_apply_mood()
	for plot in _plots:
		plot.completed.connect(_on_plot_completed)
	if GameState.has_flag(FESTIVAL_FLAG):
		festival_started.emit(false)


func _process(delta: float) -> void:
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


func _apply_mood() -> void:
	if _environment:
		_environment.adjustment_saturation = lerpf(saturation_range.x, saturation_range.y, _mood)
		_environment.background_color = sky_color_overgrown.lerp(sky_color_mowed, _mood)
	if _sun:
		_sun.light_energy = lerpf(sun_energy_range.x, sun_energy_range.y, _mood)
		_sun.light_color = sun_color_overgrown.lerp(sun_color_mowed, _mood)
