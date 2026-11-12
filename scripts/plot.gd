class_name Plot
extends Node3D
## Участок: следит за прогрессом покоса, отмечает завершение, выдаёт
## награду и штампы, подсвечивает остатки травы, хранит своё состояние.

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

const MAX_HINTS := 10
const HINT_REFRESH := 0.6

var field: MowField

var _state: Dictionary
var _hints: Array[Node3D] = []
var _hint_timer := 0.0
var _time := 0.0


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


func _process(delta: float) -> void:
	_time += delta
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = HINT_REFRESH
		_refresh_hints()
	for i in _hints.size():
		_hints[i].position.y = 0.7 + sin(_time * 2.6 + i * 1.7) * 0.14


func is_completed() -> bool:
	return _state.get("completed", false)


## Необязательный чек-лист участка: [{title, earned}].
func get_stamps() -> Array[Dictionary]:
	var finds := get_tree().get_nodes_in_group("find")
	var found := finds.filter(func(find: FindItem) -> bool: return find.is_collected()).size()
	var animals := get_tree().get_nodes_in_group("animal")
	var moved := animals.filter(func(animal: Animal) -> bool: return animal.is_moved()).size()
	var stamps: Array[Dictionary] = [
		{"title": "Выкошен", "earned": is_completed()},
		{"title": "Идеально — ни травинки", "earned": field.get_progress() >= 1.0},
	]
	if not finds.is_empty():
		stamps.append({
			"title": "Все находки (%d из %d)" % [found, finds.size()],
			"earned": found == finds.size(),
		})
	if not animals.is_empty():
		stamps.append({
			"title": "Зверьки перенесены (%d из %d)" % [moved, animals.size()],
			"earned": moved == animals.size(),
		})
	return stamps


func _on_progress_changed(ratio: float) -> void:
	if ratio >= complete_at and not is_completed():
		_state["completed"] = true
		GameState.add_coins(reward_coins)
		completed.emit()
		var camera := get_viewport().get_camera_3d() as FollowCamera
		if camera:
			camera.play_flyover()
		GameState.save_game()
	if ratio >= 1.0 and not _state.get("perfect", false):
		_state["perfect"] = true
		GameState.toast("Идеально! Ни травинки не осталось")
		GameState.save_game()


func _store_state() -> void:
	_state["mask"] = field.get_state()


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
