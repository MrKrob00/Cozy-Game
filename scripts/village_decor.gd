extends Node3D
## Земля, улица и окружение деревни: фонари, кусты, деревья вдали.
## Всё временное, из примитивов (см. Placeholder).

## Улица (мировые X, Z; ширина, длина): по ней игрок ходит между участками.
@export var street := Rect2(-11.0, 9.4, 73.0, 3.8)
@export var tree_count := 60
@export var random_seed := 11

const TRUNK := Color(0.50, 0.35, 0.25)
const POST := Color(0.30, 0.30, 0.34)
const LANTERN := Color(1.0, 0.9, 0.55)
const BAKE_CELL := 24.0
## Насколько луг выходит за участки и улицу, метры.
const MEADOW_MARGIN := 28.0
const FLAGS := [Color(1.0, 0.45, 0.45), Color(1.0, 0.82, 0.3), Color(0.45, 0.8, 1.0),
		Color(0.7, 0.55, 1.0), Color(0.55, 0.85, 0.5)]
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]


var _lamps: Array[Vector3] = []
var _trees: Array[Vector3] = []
## Где россыпям не место: [центр (x, z), радиус].
var _obstacles: Array = []
var _bunting: Node3D


func _enter_tree() -> void:
	add_to_group("walk_area")


func get_walk_rects() -> Array[Rect2]:
	return [street]


func _ready() -> void:
	# Окружение склеивается по клеткам: одна модель на клетку, но далёкие
	# клетки за кадром всё равно отсекаются.
	set_meta("bake_cell", BAKE_CELL)
	# Дорога чуть шире области, по которой ходит игрок.
	var road_rect := street.grow(0.9)
	var area := _village_area().grow(MEADOW_MARGIN)
	# Далеко за лугом — ровная заливка; её прячет дымка.
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var ground := Placeholder.part(self, plane, Meadow.GRASS_LIGHT,
			Vector3(area.get_center().x, -0.05, area.get_center().y))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Meadow.build_ground(self, area, road_rect, random_seed)
	Meadow.build_road(self, road_rect, random_seed)

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_build_street_ends(road_rect, rng)
	_build_lamps(road_rect)
	_build_near_bushes(road_rect, rng)
	_build_trees(road_rect, rng)
	_collect_obstacles()
	var free_at := _is_free.bind(road_rect)
	Meadow.scatter(self, area.grow(-6.0), free_at, _trees, random_seed + 5)
	var index := 0
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		if plot.fence == null:
			continue
		var corners := plot.fence.get_corners()
		for i in corners.size():
			Meadow.line_clumps(self, corners[i], corners[(i + 1) % corners.size()], free_at,
					random_seed + 20 + index)
			index += 1

	var village := get_tree().get_first_node_in_group("village") as Village
	if village:
		village.festival_started.connect(_on_festival_started)


# Праздник: между фонарями появляются гирлянды флажков.
func _on_festival_started(_announce: bool) -> void:
	if _bunting:
		return
	_bunting = Node3D.new()
	add_child(_bunting)
	var flag := Placeholder.prism(Vector3(0.3, 0.34, 0.03))
	var index := 0
	for i in _lamps.size() - 1:
		var from := _lamps[i] + Vector3(0.0, 2.45, 0.0)
		var to := _lamps[i + 1] + Vector3(0.0, 2.45, 0.0)
		var count := maxi(int(from.distance_to(to) / 0.55), 2)
		for k in range(1, count):
			var t := float(k) / count
			# Верёвка провисает посередине.
			var at := from.lerp(to, t) - Vector3(0.0, sin(t * PI) * 0.55, 0.0)
			var pennant := Placeholder.part(_bunting, flag, FLAGS[index % FLAGS.size()], at,
					Vector3(180.0, 0.0, 0.0))
			pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			index += 1
	Placeholder.bake_tree(_bunting)


# Кусты в торцах улицы показывают, что дальше дороги нет.
func _build_street_ends(road: Rect2, rng: RandomNumberGenerator) -> void:
	for x: float in [road.position.x - 0.6, road.end.x + 0.6]:
		var z := road.position.y - 0.5
		while z <= road.end.y + 0.5:
			_bush(Vector3(x + rng.randf_range(-0.2, 0.2), 0.0, z), rng.randf_range(0.7, 0.95), rng)
			z += 1.0


# Фонари на дальней стороне улицы: они не заслоняют игрока.
func _build_lamps(road: Rect2) -> void:
	var x := road.position.x + 3.0
	while x < road.end.x - 1.0:
		if not _inside_plot(Vector3(x, 0.0, road.position.y), 0.0, true):
			var lamp := Node3D.new()
			lamp.position = Vector3(x, 0.0, road.position.y + 0.3)
			lamp.set_meta("merge_up", true)
			add_child(lamp)
			_lamps.append(lamp.position)
			Placeholder.part(lamp, Placeholder.cylinder(0.06, 2.3), POST, Vector3(0.0, 1.15, 0.0))
			Placeholder.part(lamp, Placeholder.box(Vector3(0.3, 0.06, 0.3)), POST, Vector3(0.0, 2.52, 0.0))
			Placeholder.part(lamp, Placeholder.sphere(0.16, 8), LANTERN, Vector3(0.0, 2.36, 0.0))
		x += 7.0


# На ближней к камере стороне — только низкие кусты, чтобы ничего не заслонять.
func _build_near_bushes(road: Rect2, rng: RandomNumberGenerator) -> void:
	var x := road.position.x + 1.0
	while x < road.end.x:
		var at := Vector3(x + rng.randf_range(-0.6, 0.6), 0.0, road.end.y + rng.randf_range(0.6, 1.6))
		# Там, где с ближней стороны стоит участок, кусты не нужны.
		if not _inside_plot(at, 1.0, false):
			_bush(at, rng.randf_range(0.3, 0.5), rng)
		x += rng.randf_range(2.0, 4.0)


# Деревья растут вне участков. На дальней стороне улицы — вплотную, на ближней —
# с большим запасом, чтобы кроны не заслоняли игрока от камеры.
func _build_trees(road: Rect2, rng: RandomNumberGenerator) -> void:
	var area := Rect2(road.position.x - 25.0, road.position.y - 55.0, road.size.x + 50.0, 120.0)
	for i in tree_count * 2:
		var at := Vector3(
				rng.randf_range(area.position.x, area.end.x), 0.0,
				rng.randf_range(area.position.y, area.end.y))
		var near_side := at.z > road.position.y - 1.0
		if near_side and (at.z < road.end.y + 9.0 or _inside_plot(at, 9.0, false)):
			continue
		if _inside_plot(at, 3.5, false):
			continue
		_trees.append(at)
		var tree := Node3D.new()
		tree.position = at
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		tree.set_meta("merge_up", true)
		add_child(tree)
		var color: Color = LEAVES[rng.randi() % LEAVES.size()]
		# Деревья вдали попроще: меньше граней.
		Placeholder.part(tree, Placeholder.cylinder(0.28, 1.6, 0.2), TRUNK, Vector3(0.0, 0.8, 0.0))
		for leaves in [
			Placeholder.part(tree, Placeholder.sphere(1.3, 8), color, Vector3(0.0, 2.4, 0.0)),
			Placeholder.part(tree, Placeholder.sphere(0.95, 8), color, Vector3(0.5, 3.3, 0.2)),
			Placeholder.part(tree, Placeholder.sphere(0.8, 8), color, Vector3(-0.6, 3.0, -0.3)),
		]:
			leaves.set_meta("sway", 0.35)


func _bush(at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var color: Color = LEAVES[rng.randi() % LEAVES.size()]
	var bush := Placeholder.part(self, Placeholder.sphere(size, 8), color, at + Vector3(0.0, size * 0.55, 0.0))
	bush.set_meta("sway", 0.15)
	bush.scale = Vector3(1.0, 0.8, 1.0)


# Попадает ли точка на участок (с запасом вокруг забора) или в проём калитки.
func _inside_plot(at: Vector3, margin: float, gates_only: bool) -> bool:
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		if plot.fence and absf(plot.fence.get_gate_position().x - at.x) < plot.fence.gate_width * 0.5 + 0.6:
			if gates_only:
				return true
		if not gates_only:
			var reach := (plot.fence.fence_offset if plot.fence else 2.0) + margin
			if plot.get_inner_rect().grow(reach).has_point(Vector2(at.x, at.z)):
				return true
	return false


# Прямоугольник, в котором стоят все участки и улица.
func _village_area() -> Rect2:
	var area := street
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		area = area.merge(plot.get_inner_rect().grow(plot.fence.fence_offset if plot.fence else 2.0))
	return area


# Препятствия для россыпей: дома, деревья, ящики, жители.
func _collect_obstacles() -> void:
	_obstacles.clear()
	for node in get_tree().get_nodes_in_group("grass_shaper"):
		var prop := node as PlotProp
		if prop:
			var radius: float = {PlotProp.Kind.HOUSE: 4.4, PlotProp.Kind.SHED: 2.2}.get(prop.kind, 1.2)
			_obstacles.append([Vector2(prop.global_position.x, prop.global_position.z), radius])
	for node in get_tree().get_nodes_in_group("interactable"):
		var item := node as Node3D
		_obstacles.append([Vector2(item.global_position.x, item.global_position.z), 1.3])
	for node in get_tree().get_nodes_in_group("shadow_dynamic"):
		if node is Villager:
			_obstacles.append([Vector2(node.global_position.x, node.global_position.z), 1.0])
	for tree in _trees:
		_obstacles.append([Vector2(tree.x, tree.z), 0.7])
	for lamp in _lamps:
		_obstacles.append([Vector2(lamp.x, lamp.z), 0.5])


# Свободно ли место для россыпи: не на улице, не там, где ходят и косят, не в препятствии.
func _is_free(at: Vector2, road: Rect2) -> bool:
	if road.grow(0.4).has_point(at):
		return false
	for node in get_tree().get_nodes_in_group("walk_area"):
		if node == self:
			continue
		for rect: Rect2 in node.get_walk_rects():
			if rect.grow(0.2).has_point(at):
				return false
	for obstacle: Array in _obstacles:
		if at.distance_to(obstacle[0]) < obstacle[1]:
			return false
	return true
