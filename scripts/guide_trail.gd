class_name GuideTrail
extends Node3D
## Дорожка-указатель: стрелки на земле от игрока до калитки следующего участка.
##
## Цель даёт деревня (Village.next_goal). Путь ищется по тем же прямоугольникам,
## по которым ходит игрок: сетка, поиск в ширину от калитки, затем путь
## спрямляется. Пересчёт — только когда игрок заметно сдвинулся.

const SHADER := preload("res://shaders/guide_trail.gdshader")
## Клетка сетки поиска пути, метры.
const CELL := 0.8
## Шаг между стрелками и расстояние от игрока до первой, метры.
const SPACING := 1.25
const START_GAP := 2.0
const MAX_MARKS := 72
## Игрок сдвинулся дальше этого — дорожка перекладывается.
const REPATH_DISTANCE := 1.0
const CHECK_INTERVAL := 0.2
const LIFT := 0.1

var _village: Village
var _player: Node3D
var _terrain: Terrain
var _marks: MultiMesh
var _goal: Plot
var _origin := Vector2.ZERO
var _columns := 0
var _rows := 0
## Клетка проходима; число шагов от неё до цели (−1 — недостижима).
var _walkable := PackedByteArray()
var _steps := PackedInt32Array()
var _last_at := Vector2(INF, INF)
var _timer := 0.0
## Путь, по которому сейчас лежат стрелки: точки (x, z) от игрока до калитки.
var _path := PackedVector2Array()


func _enter_tree() -> void:
	add_to_group("guide_trail")


func _ready() -> void:
	_village = get_tree().get_first_node_in_group("village") as Village
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_terrain = Terrain.of(self)
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_custom_data = true
	_marks.mesh = _chevron()
	_marks.instance_count = MAX_MARKS
	_marks.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = "Marks"
	instance.multimesh = _marks
	var material := ShaderMaterial.new()
	material.shader = SHADER
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Стрелки разбросаны по всей деревне: отсечение по своей коробке не годится.
	instance.custom_aabb = AABB(Vector3(-200.0, -20.0, -200.0), Vector3(400.0, 60.0, 400.0))
	add_child(instance)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	if _village == null or _player == null:
		return
	var goal := _village.next_goal()
	if goal != _goal:
		_goal = goal
		_last_at = Vector2(INF, INF)
		if _goal:
			_build_field()
	if _goal == null:
		_marks.visible_instance_count = 0
		_path = PackedVector2Array()
		return
	var at := Vector2(_player.global_position.x, _player.global_position.z)
	if at.distance_to(_last_at) >= REPATH_DISTANCE:
		_last_at = at
		_path = get_path_to_goal()
		_lay(_path)


## Точки пути на земле, по которому лежат стрелки (пусто — цели нет).
## Стрелка у края экрана (GoalPointer) ведёт по ним же.
func get_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for at in _path:
		points.append(Vector3(at.x, _terrain.height_at(at), at.y))
	return points


## Сколько стрелок сейчас лежит (для проверок).
func mark_count() -> int:
	return _marks.visible_instance_count


## Путь от игрока до калитки цели: точки (x, z). Пусто, если цели или пути нет.
func get_path_to_goal() -> PackedVector2Array:
	var path := PackedVector2Array()
	if _goal == null or _player == null:
		return path
	var at := Vector2(_player.global_position.x, _player.global_position.z)
	var cell := _nearest_reachable(at)
	if cell == -1:
		return path
	path.append(at)
	# Спуск по числу шагов: каждый раз — к соседу, который ближе к цели.
	while _steps[cell] > 0:
		var next := cell
		for neighbour in _neighbours(cell):
			if _steps[neighbour] >= 0 and _steps[neighbour] < _steps[next]:
				next = neighbour
		if next == cell:
			break
		cell = next
		path.append(_cell_center(cell))
	var gate := _goal.fence.get_gate_position()
	path.append(Vector2(gate.x, gate.z))
	return _straighten(path)


# Сетка проходимости по всем местам, где ходит игрок, и число шагов до калитки.
func _build_field() -> void:
	var rects: Array[Rect2] = []
	var blockers: Array = []
	for area in get_tree().get_nodes_in_group("walk_area"):
		rects.append_array(area.get_walk_rects())
		if area.has_method("get_walk_blockers"):
			blockers.append_array(area.get_walk_blockers())
	var bounds := rects[0]
	for rect in rects:
		bounds = bounds.merge(rect)
	_origin = bounds.position
	_columns = int(ceilf(bounds.size.x / CELL))
	_rows = int(ceilf(bounds.size.y / CELL))
	_walkable.resize(_columns * _rows)
	_walkable.fill(0)
	for rect in rects:
		# Клетка проходима, если её середина внутри прямоугольника.
		var from := Vector2i(((rect.position - _origin) / CELL - Vector2(0.5, 0.5)).ceil())
		var to := Vector2i(((rect.end - _origin) / CELL - Vector2(0.5, 0.5)).floor())
		for y in range(maxi(from.y, 0), mini(to.y, _rows - 1) + 1):
			for x in range(maxi(from.x, 0), mini(to.x, _columns - 1) + 1):
				_walkable[y * _columns + x] = 1
	for blocker: Array in blockers:
		for cell in _walkable.size():
			if _walkable[cell] == 1 and _cell_center(cell).distance_to(blocker[0]) < blocker[1]:
				_walkable[cell] = 0

	_steps.resize(_walkable.size())
	_steps.fill(-1)
	var gate := _goal.fence.get_gate_position()
	var start := _cell_of(Vector2(gate.x, gate.z))
	if start == -1 or _walkable[start] == 0:
		return
	_steps[start] = 0
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for neighbour in _neighbours(cell):
			if _steps[neighbour] == -1:
				_steps[neighbour] = _steps[cell] + 1
				queue.append(neighbour)


# Проходимые соседи клетки по четырём сторонам.
func _neighbours(cell: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var x := cell % _columns
	var y := cell / _columns
	if x > 0 and _walkable[cell - 1] == 1:
		result.append(cell - 1)
	if x < _columns - 1 and _walkable[cell + 1] == 1:
		result.append(cell + 1)
	if y > 0 and _walkable[cell - _columns] == 1:
		result.append(cell - _columns)
	if y < _rows - 1 and _walkable[cell + _columns] == 1:
		result.append(cell + _columns)
	return result


func _cell_of(at: Vector2) -> int:
	var cell := Vector2i(((at - _origin) / CELL).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= _columns or cell.y >= _rows:
		return -1
	return cell.y * _columns + cell.x


func _cell_center(cell: int) -> Vector2:
	return _origin + (Vector2(cell % _columns, cell / _columns) + Vector2(0.5, 0.5)) * CELL


# Клетка под точкой или ближайшая рядом, из которой можно дойти до цели.
func _nearest_reachable(at: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := _cell_of(at + Vector2(dx, dy) * CELL)
			if cell == -1 or _steps[cell] < 0:
				continue
			var distance := _cell_center(cell).distance_to(at)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


# Убирает лишние повороты: оставляет точку, только если следующую от
# предыдущей оставленной напрямую не видно.
func _straighten(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 3:
		return path
	var result := PackedVector2Array([path[0]])
	var anchor := 0
	while anchor < path.size() - 1:
		var next := path.size() - 1
		while next > anchor + 1 and not _is_clear(path[anchor], path[next]):
			next -= 1
		result.append(path[next])
		anchor = next
	return result


func _is_clear(from: Vector2, to: Vector2) -> bool:
	var count := int(ceilf(from.distance_to(to) / (CELL * 0.4)))
	for i in range(1, count):
		var cell := _cell_of(from.lerp(to, float(i) / count))
		if cell == -1 or _walkable[cell] == 0:
			return false
	return true


# Раскладывает стрелки вдоль пути с равным шагом.
func _lay(path: PackedVector2Array) -> void:
	var count := 0
	var along := START_GAP
	var travelled := 0.0
	for i in path.size() - 1:
		var from := path[i]
		var to := path[i + 1]
		var length := from.distance_to(to)
		while along <= travelled + length and count < MAX_MARKS:
			var at := from.lerp(to, (along - travelled) / maxf(length, 0.001))
			var ahead := at + (to - from).normalized() * 0.5
			var position_3d := Vector3(at.x, _terrain.height_at(at) + LIFT, at.y)
			var ahead_3d := Vector3(ahead.x, _terrain.height_at(ahead) + LIFT, ahead.y)
			var basis := Basis.looking_at(ahead_3d - position_3d, _terrain.normal_at(at))
			_marks.set_instance_transform(count, Transform3D(basis, position_3d))
			# Первые стрелки у ног игрока появляются плавно.
			_marks.set_instance_custom_data(count, Color(count * 0.16, minf((count + 1) / 3.0, 1.0), 0.0, 0.0))
			count += 1
			along += SPACING
		travelled += length
	_marks.visible_instance_count = count


# Стрелка-уголок, лежит на земле и смотрит вдоль −Z.
func _chevron() -> ArrayMesh:
	var a := Vector3(-0.42, 0.0, 0.14)
	var b := Vector3(0.0, 0.0, -0.3)
	var c := Vector3(0.42, 0.0, 0.14)
	var d := Vector3(0.42, 0.0, 0.44)
	var e := Vector3(0.0, 0.0, 0.0)
	var f := Vector3(-0.42, 0.0, 0.44)
	var vertices := PackedVector3Array([a, b, e, a, e, f, b, c, d, b, d, e])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
