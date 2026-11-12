class_name PlotProp
extends StaticBody3D
## Крупный объект участка: дом, сарай, скамейка, дерево.
## Сам строит временную модель, коллизию и убирает траву под собой.

enum Kind { HOUSE, SHED, BENCH, TREE }

@export var kind := Kind.TREE

const CREAM := Color(0.98, 0.92, 0.78)
const ROOF := Color(0.80, 0.36, 0.30)
const WOOD := Color(0.72, 0.52, 0.34)
const WOOD_DARK := Color(0.52, 0.36, 0.24)
const GLASS := Color(0.62, 0.84, 0.94)
const STONE := Color(0.70, 0.70, 0.72)
const GOLD := Color(1.0, 0.80, 0.25)
const LEAVES := Color(0.34, 0.66, 0.34)
const LEAVES_LIGHT := Color(0.44, 0.74, 0.36)


var _windows: Array[MeshInstance3D] = []


func _enter_tree() -> void:
	add_to_group("grass_shaper")
	add_to_group("plot_light")


## Зажигает окна (вызывается, когда участок выкошен).
func light_up() -> void:
	if _windows.is_empty():
		return
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.9, 0.55)
	for window in _windows:
		window.material_override = glow


func _ready() -> void:
	match kind:
		Kind.HOUSE:
			_build_house()
		Kind.SHED:
			_build_shed()
		Kind.BENCH:
			_build_bench()
		Kind.TREE:
			_build_tree()


func shape_grass(field: MowField) -> void:
	match kind:
		Kind.HOUSE:
			field.block_rect(global_position, Vector2(6.2, 4.7), global_rotation.y)
		Kind.SHED:
			field.block_rect(global_position, Vector2(2.6, 2.4), global_rotation.y)
		Kind.BENCH:
			field.block_rect(global_position, Vector2(1.6, 0.7), global_rotation.y)
		Kind.TREE:
			field.block_circle(global_position, 0.45)


func _build_house() -> void:
	Placeholder.part(self, Placeholder.box(Vector3(6.0, 3.0, 4.5)), CREAM, Vector3(0.0, 1.5, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(6.2, 0.4, 4.7)), STONE, Vector3(0.0, 0.2, 0.0))
	Placeholder.part(self, Placeholder.prism(Vector3(6.8, 2.0, 5.2)), ROOF, Vector3(0.0, 4.0, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(0.6, 1.4, 0.6)), STONE, Vector3(1.7, 4.2, -0.8))
	# Фасад смотрит на +Z: дверь, крыльцо, окна.
	Placeholder.part(self, Placeholder.box(Vector3(1.0, 1.9, 0.12)), WOOD_DARK, Vector3(0.0, 1.15, 2.26))
	Placeholder.part(self, Placeholder.sphere(0.07), GOLD, Vector3(0.32, 1.1, 2.36))
	Placeholder.part(self, Placeholder.box(Vector3(1.6, 0.2, 0.8)), STONE, Vector3(0.0, 0.1, 2.6))
	for side: float in [-1.0, 1.0]:
		_windows.append(Placeholder.part(self, Placeholder.box(Vector3(1.1, 1.0, 0.1)), GLASS,
				Vector3(1.9 * side, 1.7, 2.26)))
		Placeholder.part(self, Placeholder.box(Vector3(1.3, 0.12, 0.2)), WOOD, Vector3(1.9 * side, 1.12, 2.3))
	# Окно на боковой стене, обращённой к камере.
	_windows.append(Placeholder.part(self, Placeholder.box(Vector3(0.1, 1.0, 1.2)), GLASS,
			Vector3(3.01, 1.7, 0.0)))
	_add_box_collision(Vector3(6.2, 3.0, 4.7), Vector3(0.0, 1.5, 0.0))


func _build_shed() -> void:
	Placeholder.part(self, Placeholder.box(Vector3(2.4, 2.0, 2.2)), WOOD, Vector3(0.0, 1.0, 0.0))
	Placeholder.part(self, Placeholder.prism(Vector3(2.9, 0.9, 2.7)), WOOD_DARK, Vector3(0.0, 2.45, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(0.9, 1.6, 0.1)), WOOD_DARK, Vector3(0.0, 0.8, 1.11))
	# Замок: сарай пока заперт.
	Placeholder.part(self, Placeholder.box(Vector3(0.2, 0.2, 0.1)), GOLD, Vector3(0.3, 0.9, 1.2))
	_add_box_collision(Vector3(2.6, 2.0, 2.4), Vector3(0.0, 1.0, 0.0))


func _build_bench() -> void:
	Placeholder.part(self, Placeholder.box(Vector3(1.5, 0.08, 0.45)), WOOD, Vector3(0.0, 0.45, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(1.5, 0.4, 0.07)), WOOD, Vector3(0.0, 0.8, -0.22), Vector3(-10.0, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(self, Placeholder.box(Vector3(0.1, 0.45, 0.42)), WOOD_DARK, Vector3(0.62 * side, 0.22, 0.0))
		Placeholder.part(self, Placeholder.box(Vector3(0.08, 0.5, 0.08)), WOOD_DARK, Vector3(0.62 * side, 0.7, -0.22))
	_add_box_collision(Vector3(1.6, 1.0, 0.6), Vector3(0.0, 0.5, 0.0))


func _build_tree() -> void:
	Placeholder.part(self, Placeholder.cylinder(0.32, 2.2, 0.22), WOOD_DARK, Vector3(0.0, 1.1, 0.0))
	Placeholder.part(self, Placeholder.sphere(1.5), LEAVES, Vector3(0.0, 3.1, 0.0))
	Placeholder.part(self, Placeholder.sphere(1.05), LEAVES_LIGHT, Vector3(0.7, 4.0, 0.3))
	Placeholder.part(self, Placeholder.sphere(0.9), LEAVES, Vector3(-0.8, 3.7, -0.4))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.4
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(shape)


func _add_box_collision(box_size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = center
	add_child(shape)
