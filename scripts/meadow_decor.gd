extends Node3D
## Окружение тестовой поляны: земля вокруг, забор и деревья.
## Всё временное, из примитивов (см. Placeholder).

## Отступ забора от края поляны в метрах.
@export var fence_offset := 2.0
@export var tree_count := 14
@export var random_seed := 7

const SURROUND := Color(0.56, 0.78, 0.44)
const WOOD := Color(0.72, 0.52, 0.34)
const TRUNK := Color(0.50, 0.35, 0.25)
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]


func _ready() -> void:
	var field := get_tree().get_first_node_in_group("mow_field") as MowField
	var half := (field.size if field else Vector2(24.0, 24.0)) * 0.5 + Vector2.ONE * fence_offset

	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	var surround := Placeholder.part(self, plane, SURROUND, Vector3(0.0, -0.02, 0.0))
	surround.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_build_fence(half)
	_build_trees(half)


func _build_fence(half: Vector2) -> void:
	var post := Placeholder.box(Vector3(0.14, 0.9, 0.14))
	for side: float in [-1.0, 1.0]:
		# Стороны вдоль X.
		var count_x := int(half.x * 2.0 / 2.0)
		for i in count_x + 1:
			var x := lerpf(-half.x, half.x, float(i) / count_x)
			Placeholder.part(self, post, WOOD, Vector3(x, 0.45, half.y * side))
		for height: float in [0.35, 0.7]:
			Placeholder.part(self, Placeholder.box(Vector3(half.x * 2.0, 0.08, 0.06)), WOOD,
					Vector3(0.0, height, half.y * side))
		# Стороны вдоль Z.
		var count_z := int(half.y * 2.0 / 2.0)
		for i in count_z + 1:
			var z := lerpf(-half.y, half.y, float(i) / count_z)
			Placeholder.part(self, post, WOOD, Vector3(half.x * side, 0.45, z))
		for height: float in [0.35, 0.7]:
			Placeholder.part(self, Placeholder.box(Vector3(0.06, 0.08, half.y * 2.0)), WOOD,
					Vector3(half.x * side, height, 0.0))


func _build_trees(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for i in tree_count:
		# Деревья стоят кольцом за забором; ближний к камере угол оставляем свободным.
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector2(cos(angle), sin(angle))
		if direction.dot(Vector2(1.0, 1.0).normalized()) > 0.55:
			continue
		var distance := maxf(half.x, half.y) * rng.randf_range(1.25, 1.9)
		var at := Vector3(direction.x * distance, 0.0, direction.y * distance)
		var scale_factor := rng.randf_range(0.8, 1.4)
		var color: Color = LEAVES[rng.randi() % LEAVES.size()]

		var tree := Node3D.new()
		tree.position = at
		tree.scale = Vector3.ONE * scale_factor
		add_child(tree)
		Placeholder.part(tree, Placeholder.cylinder(0.28, 1.6, 0.2), TRUNK, Vector3(0.0, 0.8, 0.0))
		Placeholder.part(tree, Placeholder.sphere(1.3), color, Vector3(0.0, 2.4, 0.0))
		Placeholder.part(tree, Placeholder.sphere(0.95), color, Vector3(0.5, 3.3, 0.2))
		Placeholder.part(tree, Placeholder.sphere(0.8), color, Vector3(-0.6, 3.0, -0.3))
