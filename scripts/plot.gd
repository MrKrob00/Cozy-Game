class_name Plot
extends Node3D
## Участок: следит за прогрессом покоса, отмечает завершение, выдаёт
## награду и штампы, подсвечивает остатки травы, хранит своё состояние.
## Чем больше скошено, тем ярче и теплее становится картинка.

## Участок выкошен (один раз, в момент пересечения порога).
signal completed

## Идентификатор для сохранения.
@export var plot_id := "yard"
@export var plot_name := "Двор"
## Заголовок окна завершения.
@export var completed_title := "Двор выкошен!"
@export var reward_coins := 50
## Доля покоса, при которой участок считается выкошенным.
@export_range(0.5, 1.0) var complete_at := 0.95
## Доля покоса, с которой остатки травы подсвечиваются светлячками.
@export_range(0.5, 1.0) var hints_from := 0.9

@export_group("Оживление цветом")
## Насыщенность картинки на заросшем и на выкошенном участке.
@export var saturation_range := Vector2(0.72, 1.1)
@export var sun_energy_range := Vector2(0.58, 0.74)
@export var sun_color_overgrown := Color(0.9, 0.93, 1.0)
@export var sun_color_mowed := Color(1.0, 0.95, 0.84)
@export var sky_color_overgrown := Color(0.72, 0.79, 0.82)
@export var sky_color_mowed := Color(0.66, 0.88, 0.98)

const MAX_HINTS := 10
const HINT_REFRESH := 0.6
const CHIRPS := ["chirp_1", "chirp_2", "chirp_3"]

var field: MowField

var _state: Dictionary
var _hints: Array[Node3D] = []
var _hint_timer := 0.0
var _time := 0.0
var _environment: Environment
var _sun: DirectionalLight3D
## Сглаженный прогресс, по которому меняется картинка.
var _mood := 0.0
var _chirp_timer := 3.0


func _enter_tree() -> void:
	add_to_group("plot")
	# Поле нужно другим узлам уже в их _ready, поэтому ищем его заранее.
	for child in get_children():
		if child is MowField:
			field = child


func _ready() -> void:
	_state = GameState.plot_state(plot_id)
	if _state.has("mask") and not field.set_state(_state["mask"]):
		push_warning("Сохранённый покос участка «%s» не подошёл и сброшен" % plot_id)
	field.progress_changed.connect(_on_progress_changed)
	GameState.saving.connect(_store_state)
	_build_hints()

	for child in get_children():
		if child is WorldEnvironment:
			# Копия, чтобы не менять общий ресурс сцены.
			_environment = child.environment.duplicate()
			_environment.adjustment_enabled = true
			child.environment = _environment
		elif child is DirectionalLight3D:
			_sun = child
	_mood = field.get_progress()
	_apply_mood()
	if is_completed():
		get_tree().call_group("plot_light", "light_up")


func _process(delta: float) -> void:
	_time += delta
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = HINT_REFRESH
		_refresh_hints()
	for i in _hints.size():
		_hints[i].position.y = 0.7 + sin(_time * 2.6 + i * 1.7) * 0.14

	var progress := field.get_progress()
	if not is_equal_approx(_mood, progress):
		_mood = lerpf(_mood, progress, 1.0 - exp(-1.5 * delta))
		_apply_mood()

	# Птицы: чем больше скошено, тем чаще поют.
	_chirp_timer -= delta
	if _chirp_timer <= 0.0:
		_chirp_timer = lerpf(14.0, 3.5, progress) * randf_range(0.6, 1.4)
		if progress > 0.05:
			Sfx.play(CHIRPS.pick_random(), randf_range(-16.0, -10.0), 1.0, 0.12)


func is_completed() -> bool:
	return _state.get("completed", false)


## Необязательный чек-лист участка: [{title, earned}].
func get_stamps() -> Array[Dictionary]:
	var stamps: Array[Dictionary] = [
		{"title": "Выкошен", "earned": is_completed()},
		{"title": "Идеально — ни травинки", "earned": field.get_progress() >= 1.0},
	]
	_add_count_stamp(stamps, "find", "Все находки",
			func(find: FindItem) -> bool: return find.is_collected())
	_add_count_stamp(stamps, "animal", "Зверьки перенесены",
			func(animal: Animal) -> bool: return animal.is_moved())
	_add_count_stamp(stamps, "flower_bed", "Клумбы цветут",
			func(bed: FlowerBed) -> bool: return bed.is_planted())
	return stamps


func _add_count_stamp(stamps: Array[Dictionary], group: String, title: String, done: Callable) -> void:
	var nodes := get_tree().get_nodes_in_group(group)
	if nodes.is_empty():
		return
	var count := nodes.filter(done).size()
	stamps.append({
		"title": "%s (%d из %d)" % [title, count, nodes.size()],
		"earned": count == nodes.size(),
	})


func _on_progress_changed(ratio: float) -> void:
	if ratio >= complete_at and not is_completed():
		_state["completed"] = true
		GameState.add_coins(reward_coins)
		_celebrate()
		completed.emit()
		GameState.save_game()
	if ratio >= 1.0 and not _state.get("perfect", false):
		_state["perfect"] = true
		GameState.toast("Идеально! Ни травинки не осталось")
		Sfx.play("find", -4.0, 1.2)
		GameState.save_game()


func _celebrate() -> void:
	Sfx.play("complete")
	Sfx.buzz(60)
	get_tree().call_group("plot_light", "light_up")
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		camera.play_flyover()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		Juice.confetti(self, player.global_position + Vector3.UP * 1.2)


func _store_state() -> void:
	_state["mask"] = field.get_state()


# Заросший участок блёклый и прохладный; выкошенный — яркий и тёплый.
func _apply_mood() -> void:
	if _environment:
		_environment.adjustment_saturation = lerpf(saturation_range.x, saturation_range.y, _mood)
		_environment.background_color = sky_color_overgrown.lerp(sky_color_mowed, _mood)
	if _sun:
		_sun.light_energy = lerpf(sun_energy_range.x, sun_energy_range.y, _mood)
		_sun.light_color = sun_color_overgrown.lerp(sun_color_mowed, _mood)


func _build_hints() -> void:
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = Color(1.0, 0.96, 0.55)
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.albedo_color = Color(1.0, 0.95, 0.5, 0.25)

	for i in MAX_HINTS:
		var hint := Node3D.new()
		hint.visible = false
		add_child(hint)
		for part: Array in [[0.06, core], [0.17, halo]]:
			var glow := MeshInstance3D.new()
			glow.mesh = Placeholder.sphere(part[0])
			glow.material_override = part[1]
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hint.add_child(glow)
		_hints.append(hint)


# Светлячки висят над остатками травы, когда участок почти выкошен.
func _refresh_hints() -> void:
	var progress := field.get_progress()
	var spots := PackedVector3Array()
	if progress >= hints_from and progress < 1.0:
		spots = field.get_uncut_positions(MAX_HINTS)
	for i in _hints.size():
		_hints[i].visible = i < spots.size()
		if i < spots.size():
			var at := spots[i]
			_hints[i].global_position = Vector3(at.x, _hints[i].global_position.y, at.z)
