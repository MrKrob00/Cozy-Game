extends Node3D
## Земля, улица и окружение деревни: фонари, кусты, деревья вдали.
## Всё временное, из примитивов (см. Placeholder).

## Улица (мировые X, Z; ширина, длина): по ней игрок ходит между участками.
@export var street := Rect2(-11.0, 9.4, 50.0, 3.8)
@export var tree_count := 60
@export var random_seed := 11

const GROUND := Color(0.56, 0.78, 0.44)
const ROAD := Color(0.87, 0.77, 0.56)
const ROAD_EDGE := Color(0.78, 0.67, 0.47)
const TRUNK := Color(0.50, 0.35, 0.25)
const POST := Color(0.30, 0.30, 0.34)
const LANTERN := Color(1.0, 0.9, 0.55)
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]


func _enter_tree() -> void:
	add_to_group("walk_area")


func get_walk_rects() -> Array[Rect2]:
	return [street]


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var ground := Placeholder.part(self, plane, GROUND,
			Vector3(street.get_center().x, -0.03, street.get_center().y))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Дорога чуть шире области, по которой ходит игрок.
	var road_rect := street.grow(0.9)
	for part: Array in [[road_rect.grow(0.25), ROAD_EDGE, -0.02], [road_rect, ROAD, -0.01]]:
		var rect: Rect2 = part[0]
		var road := PlaneMesh.new()
		road.size = rect.size
		var strip := Placeholder.part(self, road, part[1],
				Vector3(rect.get_center().x, part[2], rect.get_center().y))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_build_street_ends(road_rect, rng)
	_build_lamps(road_rect)
	_build_near_bushes(road_rect, rng)
	_build_trees(road_rect, rng)


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
			add_child(lamp)
			Placeholder.part(lamp, Placeholder.cylinder(0.06, 2.3), POST, Vector3(0.0, 1.15, 0.0))
			Placeholder.part(lamp, Placeholder.box(Vector3(0.3, 0.06, 0.3)), POST, Vector3(0.0, 2.52, 0.0))
			var glow := Placeholder.part(lamp, Placeholder.sphere(0.16), LANTERN, Vector3(0.0, 2.36, 0.0))
			var light := StandardMaterial3D.new()
			light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			light.albedo_color = LANTERN
			glow.material_override = light
		x += 7.0


# На ближней к камере стороне — только низкие кусты, чтобы ничего не заслонять.
func _build_near_bushes(road: Rect2, rng: RandomNumberGenerator) -> void:
	var x := road.position.x + 1.0
	while x < road.end.x:
		_bush(Vector3(x + rng.randf_range(-0.6, 0.6), 0.0, road.end.y + rng.randf_range(0.6, 1.6)),
				rng.randf_range(0.3, 0.5), rng)
		x += rng.randf_range(2.0, 4.0)


# Деревья только на дальней стороне улицы и вне участков.
func _build_trees(road: Rect2, rng: RandomNumberGenerator) -> void:
	var area := Rect2(road.position.x - 25.0, road.position.y - 55.0, road.size.x + 50.0, 54.0)
	for i in tree_count:
		var at := Vector3(
				rng.randf_range(area.position.x, area.end.x), 0.0,
				rng.randf_range(area.position.y, area.end.y))
		if _inside_plot(at, 3.5, false):
			continue
		var tree := Node3D.new()
		tree.position = at
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		add_child(tree)
		var color: Color = LEAVES[rng.randi() % LEAVES.size()]
		Placeholder.part(tree, Placeholder.cylinder(0.28, 1.6, 0.2), TRUNK, Vector3(0.0, 0.8, 0.0))
		Placeholder.part(tree, Placeholder.sphere(1.3), color, Vector3(0.0, 2.4, 0.0))
		Placeholder.part(tree, Placeholder.sphere(0.95), color, Vector3(0.5, 3.3, 0.2))
		Placeholder.part(tree, Placeholder.sphere(0.8), color, Vector3(-0.6, 3.0, -0.3))


func _bush(at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var color: Color = LEAVES[rng.randi() % LEAVES.size()]
	var bush := Placeholder.part(self, Placeholder.sphere(size), color, at + Vector3(0.0, size * 0.55, 0.0))
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
