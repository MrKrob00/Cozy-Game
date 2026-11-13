extends Node3D
## Земля, дороги и окружение деревни: фонари, поляна с дубом и прудом,
## кусты, деревья, мельница. Карту (дороги и высоты) задаёт Terrain.

@export var tree_count := 70
@export var random_seed := 11

const POST := Color(0.30, 0.30, 0.34)
const LANTERN := Color(1.0, 0.9, 0.55)
const BAKE_CELL := 24.0
## Насколько луг выходит за участки и дороги, метры.
const MEADOW_MARGIN := 28.0
## Мельница: масштаб модели и ось крыльев в координатах модели.
const WINDMILL_SCALE := 6.0
const WINDMILL_PIVOT := Vector3(0.0, 0.957, 0.332)
const WINDMILL_YAW := 2.4
## Большой дуб у площадки на поляне: (x, z) и масштаб модели.
const OAK_AT := Vector2(-28.0, 23.5)
const OAK_SCALE := 9.0
## Камера смотрит вдоль этого направления (по земле): предмет заслоняет то,
## что стоит за ним по этому направлению.
const VIEW := Vector2(-0.7071, -0.7071)
const FLAGS := [Color(1.0, 0.45, 0.45), Color(1.0, 0.82, 0.3), Color(0.45, 0.8, 1.0),
		Color(0.7, 0.55, 1.0), Color(0.55, 0.85, 0.5)]
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]

var _terrain: Terrain
## Фонари по дорогам: у каждой дороги свой ряд (между соседними — гирлянды).
var _lamp_runs: Array = []
var _trees: Array[Vector3] = []
var _windmill_fan: MeshInstance3D
## Где россыпям и деревьям не место: [центр (x, z), радиус].
var _obstacles: Array = []
var _obstacles_extra: Array = []
var _bunting: Node3D


func _enter_tree() -> void:
	add_to_group("walk_area")
	_terrain = get_parent().get_node_or_null("Terrain") as Terrain


func get_walk_rects() -> Array[Rect2]:
	return _terrain.road_rects()


func _ready() -> void:
	set_process(false)
	# Окружение склеивается по клеткам: одна модель на клетку, но далёкие
	# клетки за кадром всё равно отсекаются.
	set_meta("bake_cell", BAKE_CELL)
	var area := _terrain.bounds().grow(MEADOW_MARGIN)
	# Далеко за лугом — ровная заливка на общем уровне; её прячет дымка.
	var plane := PlaneMesh.new()
	plane.size = Vector2(500.0, 500.0)
	var ground := Placeholder.part(self, plane, Meadow.GRASS_LIGHT,
			Vector3(area.get_center().x, _terrain.far_level - 0.06, area.get_center().y))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Meadow.build_ground(self, area, random_seed, _terrain)
	Meadow.build_roads(self, random_seed, _terrain)

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_build_lamps()
	_build_glade(rng)
	_build_windmill()
	_build_trees(area.grow(-4.0), rng)
	_build_bushes(rng)
	_collect_obstacles()
	Meadow.scatter(self, area.grow(-6.0), _is_free, _trees, random_seed + 5, _terrain)
	var index := 0
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		if plot.fence == null:
			continue
		var corners := plot.fence.get_corners()
		for i in corners.size():
			Meadow.line_clumps(self, corners[i], corners[(i + 1) % corners.size()], _is_free,
					random_seed + 20 + index, _terrain)
			index += 1

	var village := get_tree().get_first_node_in_group("village") as Village
	if village:
		village.festival_started.connect(_on_festival_started)


func _process(delta: float) -> void:
	if _windmill_fan:
		_windmill_fan.rotate_object_local(Vector3.FORWARD, delta * 0.6)


# Праздник: между соседними фонарями появляются гирлянды флажков.
func _on_festival_started(_announce: bool) -> void:
	if _bunting:
		return
	_bunting = Node3D.new()
	add_child(_bunting)
	var flag := Placeholder.prism(Vector3(0.3, 0.34, 0.03))
	var index := 0
	for run: Array in _lamp_runs:
		for i in run.size() - 1:
			var from: Vector3 = run[i] + Vector3(0.0, 2.45, 0.0)
			var to: Vector3 = run[i + 1] + Vector3(0.0, 2.45, 0.0)
			# Через калитки и перекрёстки гирлянды не тянем.
			if from.distance_to(to) > 9.0:
				continue
			var count := maxi(int(from.distance_to(to) / 0.55), 2)
			var yaw := atan2(to.x - from.x, to.z - from.z) + PI * 0.5
			for k in range(1, count):
				var t := float(k) / count
				# Верёвка провисает посередине.
				var at := from.lerp(to, t) - Vector3(0.0, sin(t * PI) * 0.55, 0.0)
				var pennant := Placeholder.part(_bunting, flag, FLAGS[index % FLAGS.size()], at,
						Vector3(180.0, rad_to_deg(yaw), 0.0))
				pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				index += 1
	Placeholder.bake_tree(_bunting)


# Фонари вдоль дальнего от камеры края каждой дороги: они не заслоняют игрока.
func _build_lamps() -> void:
	var gates: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		if plot.fence:
			var gate := plot.fence.get_gate_position()
			gates.append(Vector2(gate.x, gate.z))
	for road in _terrain.roads:
		if road["name"] in ["glade", "spur"]:
			continue
		var rect: Rect2 = road["rect"]
		var along_x: bool = road["axis"] == "x"
		var length := rect.size.x if along_x else rect.size.y
		var run: Array = []
		var offset := 3.5
		while offset < length - 1.0:
			var at := Vector2(rect.position.x + offset, rect.position.y + 0.3) if along_x \
					else Vector2(rect.position.x + 0.3, rect.position.y + offset)
			offset += 7.0
			# Не ставим в проёмах калиток и на перекрёстках.
			var blocked := false
			for gate in gates:
				if at.distance_to(gate) < 3.2:
					blocked = true
			for other in _terrain.roads:
				if other != road and (other["rect"] as Rect2).grow(0.3).has_point(at):
					blocked = true
			if blocked:
				continue
			var lamp := Node3D.new()
			lamp.position = _ground(at.x, at.y)
			lamp.set_meta("merge_up", true)
			add_child(lamp)
			run.append(lamp.position)
			Placeholder.part(lamp, Placeholder.cylinder(0.06, 2.3), POST, Vector3(0.0, 1.15, 0.0))
			Placeholder.part(lamp, Placeholder.box(Vector3(0.3, 0.06, 0.3)), POST, Vector3(0.0, 2.52, 0.0))
			Placeholder.part(lamp, Placeholder.sphere(0.16, 8), LANTERN, Vector3(0.0, 2.36, 0.0))
		_lamp_runs.append(run)


# Поляна в центре кольца: большой дуб, скамейки у площадки, пруд, бочки.
# Это ориентир: её видно с любой дороги, и через неё лежит короткий путь.
func _build_glade(rng: RandomNumberGenerator) -> void:
	Models.place(self, "tree_round", _ground(OAK_AT.x, OAK_AT.y), OAK_SCALE, 1.1)
	_obstacles_extra.append([OAK_AT, 2.6])
	_trees.append(_ground(OAK_AT.x, OAK_AT.y))

	var glade: Rect2
	for road in _terrain.roads:
		if road["name"] == "glade":
			glade = road["rect"]
	# Скамейки по дальнему краю площадки, лицом к пруду.
	for x: float in [glade.position.x + 2.2, glade.position.x + 5.4]:
		var bench := PlotProp.new()
		bench.kind = PlotProp.Kind.BENCH
		bench.position = _ground(x, glade.position.y + 0.7)
		add_child(bench)
	for item: Array in [["barrel", Vector2(1.0, 6.2), 4.2], ["crate", Vector2(2.0, 6.3), 4.0],
			["sack", Vector2(1.5, 5.5), 5.0]]:
		var at: Vector2 = glade.position + item[1]
		Models.place(self, item[0], _ground(at.x, at.y), item[2], rng.randf() * TAU)
		_obstacles_extra.append([at, 0.6])

	var pond_flat: Array = _terrain.flats[0]
	var pond := PlotProp.new()
	pond.kind = PlotProp.Kind.POND
	pond.position = Vector3(pond_flat[0].x, pond_flat[2], pond_flat[0].y)
	pond.scale = Vector3.ONE * (pond_flat[1] - 0.6) / PlotProp.POND_RADIUS
	add_child(pond)
	_obstacles_extra.append([pond_flat[0], pond_flat[1] + 0.4])


# Мельница на холме за деревней: дальний ориентир. Крылья вращаются.
func _build_windmill() -> void:
	var hill: Array = _terrain.flats[1]
	var at := Vector3(hill[0].x, hill[2], hill[0].y)
	Models.place(self, "windmill", at, WINDMILL_SCALE, WINDMILL_YAW)
	_obstacles_extra.append([hill[0], hill[1]])
	_windmill_fan = Models.place(self, "windmill_fan",
			at + Vector3(0.0, WINDMILL_PIVOT.y, WINDMILL_PIVOT.z).rotated(Vector3.UP, WINDMILL_YAW) * WINDMILL_SCALE,
			WINDMILL_SCALE, WINDMILL_YAW, false)
	_windmill_fan.set_meta("no_bake", true)
	set_process(true)


# Низкие кусты вдоль дорог: по обеим сторонам, там, где свободно.
func _build_bushes(rng: RandomNumberGenerator) -> void:
	_collect_obstacles()
	for road in _terrain.roads:
		var rect: Rect2 = (road["rect"] as Rect2).grow(0.9)
		var along_x: bool = road["axis"] == "x"
		var length := rect.size.x if along_x else rect.size.y
		for side: float in [-1.0, 1.0]:
			var offset := rng.randf_range(1.0, 4.0)
			while offset < length:
				var out := rng.randf_range(0.7, 1.7)
				var at: Vector2
				if along_x:
					at = Vector2(rect.position.x + offset, (rect.position.y - out) if side < 0.0 else (rect.end.y + out))
				else:
					at = Vector2((rect.position.x - out) if side < 0.0 else (rect.end.x + out), rect.position.y + offset)
				offset += rng.randf_range(2.5, 6.0)
				if not _is_free(at):
					continue
				var size := rng.randf_range(0.3, 0.5)
				var bush := Placeholder.part(self, Placeholder.sphere(size, 8), LEAVES[rng.randi() % LEAVES.size()],
						_ground(at.x, at.y) + Vector3(0.0, size * 0.55, 0.0))
				bush.set_meta("sway", 0.15)
				bush.scale = Vector3(1.0, 0.8, 1.0)
				_obstacles_extra.append([at, size + 0.2])


# Деревья (модели KayKit) растут вне участков и дорог и только там, где
# не заслонят от камеры место, по которому ходит игрок.
func _build_trees(area: Rect2, rng: RandomNumberGenerator) -> void:
	for i in tree_count * 3:
		var spot := Vector2(rng.randf_range(area.position.x, area.end.x),
				rng.randf_range(area.position.y, area.end.y))
		if not _tree_fits(spot):
			continue
		var at := _ground(spot.x, spot.y)
		_trees.append(at)
		var pick := rng.randf()
		var model := "tree_round"
		var size := rng.randf_range(3.4, 4.6)
		if pick < 0.3:
			model = "tree_pine"
		elif pick < 0.45:
			model = "trees_round_small"
			size = rng.randf_range(3.2, 4.0)
		elif pick < 0.55:
			model = "trees_pine_small"
			size = rng.randf_range(3.4, 4.2)
		Models.place(self, model, at, size, rng.randf() * TAU)
		_obstacles_extra.append([spot, 1.6])


func _tree_fits(spot: Vector2) -> bool:
	if _terrain.road_depth(spot, 3.0) > 0.0:
		return false
	for obstacle: Array in _obstacles_extra:
		if spot.distance_to(obstacle[0]) < obstacle[1] + 2.0:
			return false
	var plots := get_tree().get_nodes_in_group("plot")
	for node in plots:
		var plot := node as Plot
		var reach := (plot.fence.fence_offset if plot.fence else 2.0) + 3.0
		if plot.get_inner_rect().grow(reach).has_point(spot):
			return false
	# Что дерево заслонит: точки за ним по направлению взгляда камеры.
	for behind: float in [1.5, 3.0, 4.5, 6.0, 7.5]:
		var hidden := spot + VIEW * behind
		if _terrain.road_depth(hidden, 0.6) > 0.0:
			return false
		for node in plots:
			if (node as Plot).get_inner_rect().grow(0.5).has_point(hidden):
				return false
	return true


# Точка на земле с высотой рельефа.
func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, _terrain.height_at(Vector2(x, z)), z)


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
	for run: Array in _lamp_runs:
		for lamp: Vector3 in run:
			_obstacles.append([Vector2(lamp.x, lamp.z), 0.5])
	_obstacles.append_array(_obstacles_extra)


# Свободно ли место для россыпи: не на дороге, не там, где ходят и косят, не в препятствии.
func _is_free(at: Vector2) -> bool:
	if _terrain.road_depth(at, 1.3) > 0.0:
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
