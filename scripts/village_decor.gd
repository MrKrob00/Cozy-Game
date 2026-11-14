extends Node3D
## Земля, дороги и окружение деревни: поляна с колодцем и дубом, дома вокруг
## неё, фонари, пруд, кусты, деревья, мельница. Карту (дороги и высоты)
## задаёт Terrain.

@export var tree_count := 70
@export var random_seed := 11

const BAKE_CELL := 24.0
## Насколько луг выходит за участки и дороги, метры.
const MEADOW_MARGIN := 28.0
## Мельница: масштаб модели и ось крыльев в координатах модели.
const WINDMILL_SCALE := 6.0
const WINDMILL_PIVOT := Vector3(0.0, 0.957, 0.332)
const WINDMILL_YAW := 0.9
## Большой дуб у дальнего угла поляны: (x, z) и масштаб модели.
const OAK_AT := Vector2(-10.6, 19.4)
const OAK_SCALE := 8.0
## Колодец посреди поляны: масштаб модели и радиус, который он занимает.
const WELL_SCALE := 3.0
const WELL_RADIUS := 1.25
## Фонарь на столбе: масштаб модели (высота около 2,7 м).
const LAMP_SCALE := 0.82
## Дома вокруг поляны: модель, место (x, z), масштаб, поворот в градусах.
## Стоят с дальней от камеры стороны и фасадом к ней, чтобы ничего не
## заслонять; ближний к камере угол поляны занят низким прудом.
const BUILDINGS := [
	["tavern", Vector2(-9.6, 13.4), 4.2, 45.0],
	["market", Vector2(7.0, 16.0), 3.0, 0.0],
	["house_c", Vector2(13.6, 16.8), 5.2, 0.0],
	["house_d", Vector2(-11.8, 33.8), 4.4, 90.0],
	["church", Vector2(-18.5, 1.0), 5.2, 45.0],
	["lumbermill", Vector2(21.5, 52.0), 3.8, -90.0],
]
## Камера смотрит вдоль этого направления (по земле): предмет заслоняет то,
## что стоит за ним по этому направлению.
const VIEW := Vector2(-0.7071, -0.7071)
const FLAGS := [Color(1.0, 0.45, 0.45), Color(1.0, 0.82, 0.3), Color(0.45, 0.8, 1.0),
		Color(0.7, 0.55, 1.0), Color(0.55, 0.85, 0.5)]
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]

var _terrain: Terrain
## Ряды фонарей: между соседними в ряду на празднике висят гирлянды.
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


## Что стоит посреди мест, где ходят: [центр (x, z), радиус]. Дорожка-указатель
## обходит эти места (игрока от них держит коллизия).
func get_walk_blockers() -> Array:
	return [[Terrain.GREEN_CENTER, WELL_RADIUS + 0.5]]


func _ready() -> void:
	set_process(false)
	var village := get_tree().get_first_node_in_group("village") as Village
	if village:
		village.festival_started.connect(_on_festival_started)
	# Окружение запечено заранее (tools/bake_map.gd): игра его только
	# загружает. Без запечённого файла строим по правилам, как при запекании.
	if MapBake.is_available():
		_load_baked()
	else:
		_generate()


# Загружает запечённое окружение и ставит ему живые материалы игры.
func _load_baked() -> void:
	var base: Node3D = (load(MapBake.BASE) as PackedScene).instantiate()
	add_child(base)
	_adopt(base)
	_lamp_runs = base.get_meta("lamp_runs", [])
	_windmill_fan = base.find_child("WindmillFan", true, false) as MeshInstance3D
	set_process(_windmill_fan != null)
	var scatter_path := MapBake.SCATTER % GameState.get_quality()
	if ResourceLoader.exists(scatter_path):
		var scatter: Node3D = (load(scatter_path) as PackedScene).instantiate()
		add_child(scatter)
		_adopt(scatter)
	Graphics.casters_changed.emit.call_deferred()


func _adopt(baked: Node3D) -> void:
	for node in baked.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		instance.material_override = Placeholder.vertex_material(instance.get_meta("receives", false))
		if instance.get_meta("caster", false):
			instance.add_to_group("shadow_caster")


# Строит окружение по правилам (при запекании и если запечённого файла нет).
func _generate() -> void:
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
	_build_green(rng)
	_build_buildings()
	_build_lamps()
	_build_pond(rng)
	_build_windmill()
	_build_trees(area.grow(-4.0), rng)
	_build_bushes(rng)
	_collect_obstacles()
	# Россыпи луга — отдельным узлом: их густота зависит от набора графики,
	# и запекаются они по файлу на набор.
	var scatter := Node3D.new()
	scatter.name = "Scatter"
	scatter.set_meta("bake_cell", BAKE_CELL)
	add_child(scatter)
	Meadow.scatter(scatter, area.grow(-6.0), _is_free, _trees, random_seed + 5, _terrain)
	var index := 0
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		if plot.fence == null:
			continue
		var corners := plot.fence.get_corners()
		for i in corners.size():
			Meadow.line_clumps(scatter, corners[i], corners[(i + 1) % corners.size()], _is_free,
					random_seed + 20 + index, _terrain)
			index += 1


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
			if from.distance_to(to) > 17.5:
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


# Фонари (модель KayKit): по углам поляны и по одному у каждой дороги,
# с дальней от камеры стороны, чтобы не заслонять игрока.
func _build_lamps() -> void:
	var green: Rect2 = _terrain.roads[0]["rect"]
	var corners: Array = []
	for corner: Vector2 in [green.position, Vector2(green.end.x, green.position.y), green.end,
			Vector2(green.position.x, green.end.y)]:
		var out := (corner - green.get_center()).sign() * 0.7
		corners.append(_add_lamp(corner + out, atan2(-out.x, -out.y)))
	# Гирлянды на празднике идут по кругу вокруг поляны.
	corners.append(corners[0])
	_lamp_runs.append(corners)
	for road in _terrain.roads:
		if road.get("green", false):
			continue
		var rect: Rect2 = road["rect"]
		var middle := rect.get_center()
		if road["axis"] == "x":
			_add_lamp(Vector2(middle.x, rect.position.y - 0.7), 0.0)
		else:
			_add_lamp(Vector2(rect.position.x - 0.7, middle.y), PI * 0.5)


# Ставит фонарь; yaw — куда смотрит его кронштейн. Возвращает точку на земле.
func _add_lamp(at: Vector2, yaw: float) -> Vector3:
	var ground := _ground(at.x, at.y)
	Models.place(self, "post_lantern", ground, LAMP_SCALE, yaw)
	_obstacles_extra.append([at, 0.5])
	return ground


# Поляна в середине деревни: колодец, большой дуб, скамейки, бочки у рынка.
# Сюда выходят все дороги, отсюда видны все калитки.
func _build_green(rng: RandomNumberGenerator) -> void:
	var center := Terrain.GREEN_CENTER
	var well := StaticBody3D.new()
	well.name = "GreenWell"
	well.position = _ground(center.x, center.y)
	add_child(well)
	Models.place(well, "well", Vector3.ZERO, WELL_SCALE, PI * 0.25)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = WELL_RADIUS
	cylinder.height = 1.6
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.8, 0.0)
	well.add_child(shape)

	Models.place(self, "tree_round", _ground(OAK_AT.x, OAK_AT.y), OAK_SCALE, 1.1)
	_obstacles_extra.append([OAK_AT, 2.6])
	_trees.append(_ground(OAK_AT.x, OAK_AT.y))

	var green: Rect2 = _terrain.roads[0]["rect"]
	# Скамейки по дальним краям поляны, лицом к колодцу.
	for item: Array in [[Vector2(-5.0, green.position.y + 0.6), 0.0], [Vector2(4.6, green.position.y + 0.6), 0.0],
			[Vector2(green.position.x + 0.6, 30.4), PI * 0.5]]:
		var bench := PlotProp.new()
		bench.kind = PlotProp.Kind.BENCH
		bench.position = _ground(item[0].x, item[0].y)
		bench.rotation.y = item[1]
		add_child(bench)
	# Товар у рынка и у таверны.
	for item: Array in [["barrel", Vector2(10.6, 19.4), 4.2], ["crate", Vector2(11.4, 20.2), 4.0],
			["sack", Vector2(10.2, 20.5), 5.0], ["crate_long", Vector2(3.6, 18.3), 4.0],
			["barrel", Vector2(-6.2, 16.8), 4.2], ["barrel", Vector2(-5.4, 17.5), 3.6],
			["pumpkin", Vector2(-9.2, 30.2), 0.55], ["pumpkin_small", Vector2(-9.9, 30.9), 0.55],
			["stone_pile", Vector2(9.8, 30.6), 3.4]]:
		var at: Vector2 = item[1]
		Models.place(self, item[0], _ground(at.x, at.y), item[2], rng.randf() * TAU)
		_obstacles_extra.append([at, 0.7])


# Дома вокруг поляны — модели KayKit.
func _build_buildings() -> void:
	for item: Array in BUILDINGS:
		var at: Vector2 = item[1]
		var mesh := Models.mesh(item[0])
		var size := mesh.get_aabb().size * (item[2] as float)
		# Дом стоит на склоне: опускаем его к самой низкой точке под ним.
		var base := INF
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			base = minf(base, _terrain.height_at(at + corner * Vector2(size.x, size.z) * 0.4))
		Models.place(self, item[0], Vector3(at.x, base - 0.05, at.y), item[2], deg_to_rad(item[3]))
		_obstacles_extra.append([at, maxf(size.x, size.z) * 0.6])


# Пруд в ближнем к камере углу у поляны: низкий, ничего не заслоняет.
func _build_pond(rng: RandomNumberGenerator) -> void:
	var flat: Array = _terrain.flats[0]
	var pond := PlotProp.new()
	pond.kind = PlotProp.Kind.POND
	pond.position = Vector3(flat[0].x, flat[2], flat[0].y)
	pond.scale = Vector3.ONE * (flat[1] - 0.6) / PlotProp.POND_RADIUS
	add_child(pond)
	_obstacles_extra.append([flat[0], flat[1] + 0.4])
	# Осока по берегу.
	for i in 9:
		var angle := rng.randf() * TAU
		var at: Vector2 = flat[0] + Vector2(cos(angle), sin(angle)) * (flat[1] - 0.35)
		Models.place(self, "waterplant_a" if i % 2 == 0 else "waterplant_b", Vector3(at.x, flat[2], at.y),
				rng.randf_range(3.6, 5.2), rng.randf() * TAU, false)


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
	_windmill_fan.name = "WindmillFan"
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
		var pick := rng.randf()
		# Изредка вместо дерева — пень.
		if pick > 0.93:
			Models.place(self, "stump_a" if pick > 0.965 else "stump_b", at, rng.randf_range(2.6, 3.4), rng.randf() * TAU)
			_obstacles_extra.append([spot, 0.8])
			continue
		_trees.append(at)
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
	_obstacles.append_array(_obstacles_extra)


# Свободно ли место для россыпи: не на дороге, не внутри заборов (там газон
# участка), не там, где ходят, не в препятствии.
func _is_free(at: Vector2) -> bool:
	if _terrain.road_depth(at, 1.3) > 0.0:
		return false
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		var offset := plot.fence.fence_offset if plot.fence else 2.0
		if plot.get_inner_rect().grow(offset - Plot.WALK_MARGIN + 0.45).has_point(at):
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
