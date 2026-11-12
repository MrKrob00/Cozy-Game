extends Node3D
## Окружение участка: земля вокруг, забор с калиткой и деревья вдали.
## Всё временное, из примитивов (см. Placeholder).

## Отступ забора от края поля в метрах.
@export var fence_offset := 2.0
## Забор с дальней стороны (−Z). Выключается, если там стоит дом.
@export var fence_back := true
## Положение калитки по X на ближней стороне (+Z) и её ширина.
@export var gate_x := 0.0
@export var gate_width := 2.4
@export var tree_count := 16
@export var random_seed := 7

const SURROUND := Color(0.56, 0.78, 0.44)
const WOOD := Color(0.72, 0.52, 0.34)
const TRUNK := Color(0.50, 0.35, 0.25)
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]
const POST_SPACING := 2.0


func _ready() -> void:
	var field := get_tree().get_first_node_in_group("mow_field") as MowField
	var half := (field.size if field else Vector2(24.0, 24.0)) * 0.5 + Vector2.ONE * fence_offset

	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	var surround := Placeholder.part(self, plane, SURROUND, Vector3(0.0, -0.02, 0.0))
	surround.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Боковые стороны.
	for side: float in [-1.0, 1.0]:
		_fence_run(Vector3(half.x * side, 0.0, -half.y), Vector3(half.x * side, 0.0, half.y))
	if fence_back:
		_fence_run(Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y))
	# Ближняя сторона с проёмом калитки.
	var gate_left := gate_x - gate_width * 0.5
	var gate_right := gate_x + gate_width * 0.5
	_fence_run(Vector3(-half.x, 0.0, half.y), Vector3(gate_left, 0.0, half.y))
	_fence_run(Vector3(gate_right, 0.0, half.y), Vector3(half.x, 0.0, half.y))
	for x: float in [gate_left, gate_right]:
		Placeholder.part(self, Placeholder.box(Vector3(0.2, 1.3, 0.2)), WOOD, Vector3(x, 0.65, half.y))
		Placeholder.part(self, Placeholder.sphere(0.14), WOOD, Vector3(x, 1.36, half.y))

	_build_trees(half)


func _fence_run(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var yaw := atan2(to.x - from.x, to.z - from.z)
	var posts := maxi(roundi(length / POST_SPACING), 1)
	var post := Placeholder.box(Vector3(0.14, 0.9, 0.14))
	for i in posts + 1:
		Placeholder.part(self, post, WOOD, from.lerp(to, float(i) / posts) + Vector3(0.0, 0.45, 0.0))
	for height: float in [0.35, 0.7]:
		var rail := Placeholder.part(self, Placeholder.box(Vector3(0.06, 0.08, length)), WOOD,
				(from + to) * 0.5 + Vector3(0.0, height, 0.0))
		rail.rotation.y = yaw


func _build_trees(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for i in tree_count:
		# Деревья стоят кольцом вдали; ближний к камере угол оставляем свободным.
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector2(cos(angle), sin(angle))
		if direction.dot(Vector2(1.0, 1.0).normalized()) > 0.5:
			continue
		var distance := maxf(half.x, half.y) * rng.randf_range(1.9, 2.8)
		var scale_factor := rng.randf_range(0.8, 1.4)
		var color: Color = LEAVES[rng.randi() % LEAVES.size()]

		var tree := Node3D.new()
		tree.position = Vector3(direction.x * distance, 0.0, direction.y * distance)
		tree.scale = Vector3.ONE * scale_factor
		add_child(tree)
		Placeholder.part(tree, Placeholder.cylinder(0.28, 1.6, 0.2), TRUNK, Vector3(0.0, 0.8, 0.0))
		Placeholder.part(tree, Placeholder.sphere(1.3), color, Vector3(0.0, 2.4, 0.0))
		Placeholder.part(tree, Placeholder.sphere(0.95), color, Vector3(0.5, 3.3, 0.2))
		Placeholder.part(tree, Placeholder.sphere(0.8), color, Vector3(-0.6, 3.0, -0.3))
