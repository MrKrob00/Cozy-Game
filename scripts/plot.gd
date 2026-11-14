class_name Plot
extends Node3D
## Участок деревни: поле с травой и всё, что на нём стоит.
##
## Следит за прогрессом покоса, отмечает завершение, выдаёт награду и
## штампы, подсвечивает остатки травы, хранит своё состояние. Участок может
## быть закрыт, пока не выкошен другой.

## Участок выкошен (один раз, в момент пересечения порога).
signal completed
## Скошено достаточно, чтобы открылся следующий участок (один раз).
signal next_opened
## Калитка участка открылась.
signal unlocked
## Скошена очередная четверть участка (25, 50 или 75 %).
signal milestone(percent: int)

## Идентификатор для сохранения.
@export var plot_id := "yard"
@export var plot_name := "Двор"
## Заголовок окна завершения.
@export var completed_title := "Двор выкошен!"
@export var reward_coins := 50
## Участок, который нужно выкосить, чтобы открылся этот (пусто — открыт сразу).
@export var requires_plot := ""
## Сообщение, когда участок открывается.
@export var unlock_text := ""
## Сообщение, если подойти к закрытой калитке.
@export var locked_text := ""
## Доля покоса, при которой участок считается выкошенным.
@export_range(0.5, 1.0) var complete_at := 0.95
## Доля покоса, при которой открывается следующий участок: ждать, пока этот
## будет докошен до травинки, не нужно.
@export_range(0.3, 1.0) var open_next_at := 0.8
## Доля покоса, с которой остатки травы подсвечиваются светлячками.
@export_range(0.5, 1.0) var hints_from := 0.9

## Насколько игрок может выйти за край поля (чтобы докосить края и развернуться).
const WALK_MARGIN := 1.1
const MILESTONES := [25, 50, 75]
const MAX_HINTS := 10
## Птицы прилетают на газон, когда скошена эта доля участка; сколько их.
const BIRDS_FROM := 0.5
const BIRD_COUNT := 2
const HINT_REFRESH := 0.6

var field: MowField
var fence: PlotFence
## Участок уже открыт по правилам игры, но игрок ещё не видел, как
## открывается калитка: до показа (reveal) она остаётся закрытой.
var reveal_pending := false

var _state: Dictionary
var _hints: Array[Node3D] = []
var _hint_timer := 0.0
var _time := 0.0
var _locked_toast_cooldown := 0.0
var _birds: Array[LawnBird] = []


## Участок, которому принадлежит узел (ближайший предок-участок).
static func of(node: Node) -> Plot:
	var current := node
	while current:
		if current is Plot:
			return current
		current = current.get_parent()
	return null


func _enter_tree() -> void:
	add_to_group("plot")
	add_to_group("walk_area")
	# Поле и забор нужны другим узлам уже в их _ready, поэтому ищем их заранее.
	for child in get_children():
		if child is MowField:
			field = child
		elif child is PlotFence:
			fence = child
	# Газон участка тянется до самого забора.
	if field and fence:
		field.apron = fence.fence_offset + 0.3


func _ready() -> void:
	_state = GameState.plot_state(plot_id)
	if _state.has("mask") and not field.set_state(_state["mask"]):
		push_warning("Сохранённый покос участка «%s» не подошёл и сброшен" % plot_id)
	field.progress_changed.connect(_on_progress_changed)
	field.leftovers_cleared.connect(_on_leftovers_cleared)
	GameState.saving.connect(_store_state)
	GameState.day_started.connect(_on_day_started)
	_build_hints()

	if requires_plot != "":
		for other: Plot in get_tree().get_nodes_in_group("plot"):
			if other.plot_id == requires_plot:
				other.next_opened.connect(_on_required_plot_opened)
	if fence:
		fence.set_gate_open(is_unlocked(), false)
	if is_completed():
		_light_up()
	_update_birds(field.get_progress())


func _process(delta: float) -> void:
	_time += delta
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = HINT_REFRESH
		_refresh_hints()
	for i in _hints.size():
		_hints[i].position.y = 0.7 + sin(_time * 2.6 + i * 1.7) * 0.14
	_locked_toast_cooldown -= delta
	if not is_unlocked() and _locked_toast_cooldown <= 0.0:
		_check_locked_gate()
	# Показ не случился, а игрок уже у калитки: открываем без камеры.
	if reveal_pending and fence and _gate_distance() < 3.5:
		reveal()


func is_completed() -> bool:
	return _state.get("completed", false)


func is_unlocked() -> bool:
	return requires_plot == "" or GameState.has_plot_opened_next(requires_plot)


func get_progress() -> float:
	return field.get_progress()


## Насколько участок «ожил», 0–1: по нему подстраивается картинка.
## Выкошенный участок остаётся почти ярким, даже когда трава отросла.
func get_mood() -> float:
	var progress := field.get_progress()
	return lerpf(0.8, 1.0, progress) if is_completed() else progress


## Узлы группы, принадлежащие этому участку.
func members(group: String) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group(group):
		if is_ancestor_of(node):
			result.append(node)
	return result


## Прямоугольник (мировые X, Z), по которому игрок ходит внутри участка.
func get_inner_rect() -> Rect2:
	var local_half := field.size * 0.5 + Vector2.ONE * WALK_MARGIN
	# Участок может быть повёрнут на 90° или 180°.
	var axis_x := field.global_basis.x
	var axis_z := field.global_basis.z
	var half := Vector2(
			absf(axis_x.x) * local_half.x + absf(axis_z.x) * local_half.y,
			absf(axis_x.z) * local_half.x + absf(axis_z.z) * local_half.y)
	var center := Vector2(field.global_position.x, field.global_position.z)
	return Rect2(center - half, half * 2.0)


## Где можно ходить: сам участок и проход через калитку, если она открыта.
func get_walk_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [get_inner_rect()]
	if fence and is_unlocked() and not reveal_pending:
		rects.append(fence.get_gate_rect(WALK_MARGIN))
	return rects


## Расстояние от точки до участка (0 — внутри).
func distance_to(world_position: Vector3) -> float:
	var rect := get_inner_rect()
	var point := Vector2(world_position.x, world_position.z)
	return point.distance_to(point.clamp(rect.position, rect.end))


## Необязательный чек-лист участка: [{title, earned}].
func get_stamps() -> Array[Dictionary]:
	var stamps: Array[Dictionary] = [
		{"title": L.t("Выкошен"), "earned": is_completed()},
		{"title": L.t("Идеально — ни травинки"), "earned": _state.get("perfect", false)},
	]
	_add_count_stamp(stamps, "find", "Все находки",
			func(find: FindItem) -> bool: return find.is_collected())
	_add_count_stamp(stamps, "animal", "Зверьки перенесены",
			func(animal: Animal) -> bool: return animal.is_moved())
	_add_count_stamp(stamps, "flower_bed", "Клумбы цветут",
			func(bed: FlowerBed) -> bool: return bed.is_planted())
	_add_count_stamp(stamps, "stone", "Камни убраны",
			func(stone: Stone) -> bool: return stone.is_removed())
	_add_count_stamp(stamps, "repairable", "Всё починено",
			func(item: Repairable) -> bool: return item.is_repaired())
	return stamps


func _add_count_stamp(stamps: Array[Dictionary], group: String, title: String, done: Callable) -> void:
	var nodes := members(group)
	if nodes.is_empty():
		return
	var count := nodes.filter(done).size()
	stamps.append({
		"title": L.t("%s (%d из %d)") % [L.t(title), count, nodes.size()],
		"earned": count == nodes.size(),
	})


func _on_progress_changed(ratio: float) -> void:
	_update_birds(ratio)
	if not is_completed():
		var reached: Array = _state.get("milestones", [])
		for percent: int in MILESTONES:
			if ratio * 100.0 >= percent and not percent in reached:
				reached.append(percent)
				_state["milestones"] = reached
				milestone.emit(percent)
	if ratio >= minf(open_next_at, complete_at) and not _state.get("next_opened", false):
		_state["next_opened"] = true
		# Мелкие клочки по всему участку убираются сами: докашивать легче.
		_sweep_leftovers()
		next_opened.emit()
		GameState.save_game()
	if ratio >= complete_at and not is_completed():
		_state["completed"] = true
		_state["tidy"] = true
		GameState.add_coins(reward_coins, _player_position())
		_celebrate()
		completed.emit()
		_sweep_leftovers()
		GameState.save_game()
	elif ratio >= complete_at and not _state.get("tidy", true):
		# Трава отросла, и её снова подстригли: небольшая благодарность.
		_state["tidy"] = true
		var thanks := maxi(reward_coins / 5, 5)
		GameState.add_coins(thanks, _player_position())
		GameState.toast(L.t("%s снова ухожен: +%d монет") % [L.t(plot_name), thanks])
		Sfx.play("coin")
		GameState.save_game()
	if ratio >= 1.0 and not _state.get("perfect", false):
		_state["perfect"] = true
		GameState.toast("Идеально! Ни травинки не осталось")
		Sfx.play("find", -4.0, 1.2)
		GameState.save_game()


# Убирает мелкие остатки травы по всему участку: поле обходит себя само,
# понемногу за кадр, а срезанное идёт в мешок.
func _sweep_leftovers() -> void:
	field.sweep_leftovers(GameState.upgrade_level("blade") >= 1)


func _on_leftovers_cleared(units: float, spots: PackedVector3Array) -> void:
	GameState.add_grass(units)
	for spot in spots:
		Juice.sparkle(self, spot + Vector3.UP * 0.2, Color(0.72, 0.95, 0.42), 5)


# Птицы на газоне: появляются, когда скошена половина участка, и улетают,
# если трава снова отросла.
func _update_birds(ratio: float) -> void:
	if ratio >= BIRDS_FROM and _birds.is_empty():
		for i in BIRD_COUNT:
			_birds.append(LawnBird.spawn(self, hash(plot_id) + i))
	elif ratio < BIRDS_FROM * 0.6 and not _birds.is_empty():
		for bird in _birds:
			if is_instance_valid(bird):
				bird.queue_free()
		_birds.clear()


func _on_day_started(_day: int) -> void:
	if is_completed():
		field.regrow()
		_state["tidy"] = false


func _player_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player.global_position + Vector3.UP * 1.4 if player else global_position


# Предыдущий участок выкошен на open_next_at. Калитку открывает не сам
# участок, а показ: камера едет к калитке, и она распахивается на глазах
# у игрока (его запускает интерфейс).
func _on_required_plot_opened() -> void:
	reveal_pending = true


## Открывает калитку на глазах у игрока (см. reveal_pending).
func reveal() -> void:
	if not reveal_pending:
		return
	reveal_pending = false
	if fence:
		fence.set_gate_open(true, true)
		fence.show_guide_arrow(self)
	unlocked.emit()
	if unlock_text != "":
		GameState.toast(unlock_text)


func _celebrate() -> void:
	Sfx.play("complete")
	Sfx.buzz(60)
	_light_up()
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		camera.play_flyover()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		Juice.confetti(self, player.global_position + Vector3.UP * 1.2)
		player.celebrate()


# Зажигает окна домов на участке.
func _light_up() -> void:
	for prop in members("plot_light"):
		prop.light_up()


func _store_state() -> void:
	_state["mask"] = field.get_state()


# Расстояние от игрока до калитки по земле.
func _gate_distance() -> float:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or fence == null:
		return INF
	var gate := fence.get_gate_position()
	return Vector2(player.global_position.x - gate.x, player.global_position.z - gate.z).length()


# Подсказка, если игрок подошёл к закрытой калитке.
func _check_locked_gate() -> void:
	if fence == null or locked_text == "":
		return
	if _gate_distance() < 2.6:
		_locked_toast_cooldown = 10.0
		GameState.toast(locked_text)
		Sfx.play("deny", -6.0)


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
