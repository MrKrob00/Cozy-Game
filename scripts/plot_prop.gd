class_name PlotProp
extends StaticBody3D
## Крупный объект участка: дом, сарай, скамейка, дерево.
## Сам строит временную модель, коллизию и убирает траву под собой.

enum Kind { HOUSE, SHED, BENCH, TREE, WELL, FOUNTAIN, POND }

@export var kind := Kind.TREE
## Цвета стен и крыши дома.
@export var wall_color := Color(0.98, 0.92, 0.78)
@export var roof_color := Color(0.80, 0.36, 0.30)
## Дерево с яблоками.
@export var fruit := false

const WOOD := Color(0.72, 0.52, 0.34)
const WOOD_DARK := Color(0.52, 0.36, 0.24)
const GLASS := Color(0.62, 0.84, 0.94)
const STONE := Color(0.70, 0.70, 0.72)
const GOLD := Color(1.0, 0.80, 0.25)
const LEAVES := Color(0.34, 0.66, 0.34)
const LEAVES_LIGHT := Color(0.44, 0.74, 0.36)


const DOOR_OPEN_ANGLE := -1.9
const POND_RADIUS := 2.8
## Насколько растворяется крона, когда заслоняет игрока.
const CROWN_FADE := 0.3

var _windows: Array[MeshInstance3D] = []
var _door: Node3D
var _padlock: MeshInstance3D
var _crown_material: ShaderMaterial
var _crown_light_material: ShaderMaterial
var _apple_material: ShaderMaterial
var _crown_fade := 1.0
# Части фонтана, которые меняются после починки.
var _fountain_broken: Node3D
var _fountain_fixed: Node3D


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
		Kind.WELL:
			_build_well()
		Kind.FOUNTAIN:
			_build_fountain()
		Kind.POND:
			_build_pond()
	set_process(kind == Kind.TREE)


func _process(delta: float) -> void:
	_update_crown_fade(delta)


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
		Kind.WELL:
			field.block_circle(global_position, 0.9)
		Kind.FOUNTAIN:
			field.block_circle(global_position, 2.0)
		Kind.POND:
			field.block_circle(global_position, POND_RADIUS + 0.25)


func _build_house() -> void:
	Placeholder.part(self, Placeholder.box(Vector3(6.0, 3.0, 4.5)), wall_color, Vector3(0.0, 1.5, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(6.2, 0.4, 4.7)), STONE, Vector3(0.0, 0.2, 0.0))
	Placeholder.part(self, Placeholder.prism(Vector3(6.8, 2.0, 5.2)), roof_color, Vector3(0.0, 4.0, 0.0))
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
	# Дверь на петлях у левого края; тёмный проём за ней виден, когда она открыта.
	Placeholder.part(self, Placeholder.box(Vector3(0.9, 1.6, 0.04)), Color(0.2, 0.16, 0.14), Vector3(0.0, 0.8, 1.09))
	_door = Node3D.new()
	_door.position = Vector3(-0.45, 0.0, 1.12)
	add_child(_door)
	Placeholder.part(_door, Placeholder.box(Vector3(0.9, 1.6, 0.08)), WOOD_DARK, Vector3(0.45, 0.8, 0.0))
	# Замок: сарай пока заперт.
	_padlock = Placeholder.part(_door, Placeholder.box(Vector3(0.2, 0.2, 0.1)), GOLD, Vector3(0.75, 0.9, 0.08))
	_add_box_collision(Vector3(2.6, 2.0, 2.4), Vector3(0.0, 1.0, 0.0))


## Отпирает сарай: замок пропадает, дверь распахивается.
func set_unlocked(animated: bool) -> void:
	if _door == null:
		return
	_padlock.visible = false
	if not animated:
		_door.rotation.y = DOOR_OPEN_ANGLE
		return
	Juice.sparkle(self, _padlock.global_position)
	var tween := create_tween()
	tween.tween_property(_door, "rotation:y", DOOR_OPEN_ANGLE, 0.8) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_well() -> void:
	Placeholder.part(self, Placeholder.cylinder(0.75, 0.7), STONE, Vector3(0.0, 0.35, 0.0))
	Placeholder.part(self, Placeholder.cylinder(0.58, 0.04), Color(0.25, 0.45, 0.6), Vector3(0.0, 0.7, 0.0))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(self, Placeholder.box(Vector3(0.12, 1.5, 0.12)), WOOD_DARK, Vector3(0.68 * side, 1.2, 0.0))
	Placeholder.part(self, Placeholder.cylinder(0.06, 1.4), WOOD, Vector3(0.0, 1.6, 0.0), Vector3(0.0, 0.0, 90.0))
	Placeholder.part(self, Placeholder.prism(Vector3(1.9, 0.6, 1.3)), roof_color, Vector3(0.0, 2.2, 0.0))
	Placeholder.part(self, Placeholder.cylinder(0.14, 0.24, 0.17), WOOD, Vector3(0.2, 1.15, 0.0))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.8
	cylinder.height = 1.4
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.7, 0.0)
	add_child(shape)


func _build_bench() -> void:
	Placeholder.part(self, Placeholder.box(Vector3(1.5, 0.08, 0.45)), WOOD, Vector3(0.0, 0.45, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(1.5, 0.4, 0.07)), WOOD, Vector3(0.0, 0.8, -0.22), Vector3(-10.0, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(self, Placeholder.box(Vector3(0.1, 0.45, 0.42)), WOOD_DARK, Vector3(0.62 * side, 0.22, 0.0))
		Placeholder.part(self, Placeholder.box(Vector3(0.08, 0.5, 0.08)), WOOD_DARK, Vector3(0.62 * side, 0.7, -0.22))
	_add_box_collision(Vector3(1.6, 1.0, 0.6), Vector3(0.0, 0.5, 0.0))


func _build_tree() -> void:
	Placeholder.part(self, Placeholder.cylinder(0.32, 2.2, 0.22), WOOD_DARK, Vector3(0.0, 1.1, 0.0))
	# У кроны свои материалы: она растворяется, когда заслоняет игрока.
	_crown_material = Placeholder.material(LEAVES).duplicate()
	_crown_light_material = Placeholder.material(LEAVES_LIGHT).duplicate()
	var crown: Array[MeshInstance3D] = [
		Placeholder.part(self, Placeholder.sphere(1.5), LEAVES, Vector3(0.0, 3.1, 0.0)),
		Placeholder.part(self, Placeholder.sphere(1.05), LEAVES_LIGHT, Vector3(0.7, 4.0, 0.3)),
		Placeholder.part(self, Placeholder.sphere(0.9), LEAVES, Vector3(-0.8, 3.7, -0.4)),
	]
	crown[0].material_override = _crown_material
	crown[1].material_override = _crown_light_material
	crown[2].material_override = _crown_material
	if fruit:
		var apple_material: ShaderMaterial = Placeholder.material(Color(0.92, 0.26, 0.24)).duplicate()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name)
		for i in 9:
			var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.6),
					rng.randf_range(-1.0, 1.0)).normalized()
			var apple := Placeholder.part(self, Placeholder.sphere(0.14), Color.WHITE,
					Vector3(0.0, 3.1, 0.0) + direction * 1.5)
			apple.material_override = apple_material
		_apple_material = apple_material
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.4
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(shape)


# Крона заслоняет игрока, если стоит между ним и камерой: тогда она растворяется точками.
func _update_crown_fade(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if camera == null or player == null or _crown_material == null:
		return
	var view := -camera.global_basis.z
	view.y = 0.0
	view = view.normalized()
	var offset := player.global_position - global_position
	offset.y = 0.0
	# Вдоль взгляда игрок должен быть за деревом, поперёк — в пределах кроны.
	var along := offset.dot(view)
	var across := absf(offset.cross(view).y)
	var hidden := along > 0.6 and along < 5.2 and across < 1.9
	var target := CROWN_FADE if hidden else 1.0
	if is_equal_approx(_crown_fade, target):
		return
	_crown_fade = move_toward(_crown_fade, target, delta * 3.0)
	for crown_material: ShaderMaterial in [_crown_material, _crown_light_material, _apple_material]:
		if crown_material:
			crown_material.set_shader_parameter("fade", _crown_fade)


## Чинит фонтан: чаша светлеет, появляется вода и струя.
func set_repaired(_animated: bool) -> void:
	if _fountain_fixed == null:
		return
	_fountain_broken.visible = false
	_fountain_fixed.visible = true


func _build_fountain() -> void:
	const OLD_STONE := Color(0.56, 0.55, 0.52)
	const NEW_STONE := Color(0.86, 0.84, 0.8)
	const WATER := Color(0.42, 0.72, 0.92)
	const MOSS := Color(0.36, 0.5, 0.3)

	# Заброшенный: тёмный камень, сухая чаша во мху, покосившаяся верхушка.
	_fountain_broken = Node3D.new()
	add_child(_fountain_broken)
	Placeholder.part(_fountain_broken, Placeholder.cylinder(1.8, 0.5), OLD_STONE, Vector3(0.0, 0.25, 0.0))
	Placeholder.part(_fountain_broken, Placeholder.cylinder(1.5, 0.04), MOSS, Vector3(0.0, 0.5, 0.0))
	Placeholder.part(_fountain_broken, Placeholder.cylinder(0.3, 1.1), OLD_STONE, Vector3(0.0, 0.9, 0.0))
	Placeholder.part(_fountain_broken, Placeholder.cylinder(0.3, 0.2, 0.7), OLD_STONE,
			Vector3(0.12, 1.5, 0.0), Vector3(0.0, 0.0, -16.0))
	Placeholder.part(_fountain_broken, Placeholder.box(Vector3(0.5, 0.3, 0.4)), OLD_STONE,
			Vector3(1.1, 0.62, 0.5), Vector3(20.0, 30.0, 10.0))

	# Починенный: светлый камень, вода, струя.
	_fountain_fixed = Node3D.new()
	_fountain_fixed.visible = false
	add_child(_fountain_fixed)
	Placeholder.part(_fountain_fixed, Placeholder.cylinder(1.8, 0.5), NEW_STONE, Vector3(0.0, 0.25, 0.0))
	Placeholder.part(_fountain_fixed, Placeholder.cylinder(1.55, 0.04), WATER, Vector3(0.0, 0.5, 0.0))
	Placeholder.part(_fountain_fixed, Placeholder.cylinder(0.3, 1.1), NEW_STONE, Vector3(0.0, 0.9, 0.0))
	Placeholder.part(_fountain_fixed, Placeholder.cylinder(0.3, 0.2, 0.75), NEW_STONE, Vector3(0.0, 1.5, 0.0))
	Placeholder.part(_fountain_fixed, Placeholder.cylinder(0.62, 0.03), WATER, Vector3(0.0, 1.6, 0.0))
	var jet := CPUParticles3D.new()
	jet.position = Vector3(0.0, 1.65, 0.0)
	jet.amount = 60
	jet.lifetime = 1.1
	jet.mesh = Placeholder.sphere(0.05)
	var drops := StandardMaterial3D.new()
	drops.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drops.albedo_color = Color(0.75, 0.9, 1.0)
	jet.material_override = drops
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jet.direction = Vector3.UP
	jet.spread = 14.0
	jet.initial_velocity_min = 3.6
	jet.initial_velocity_max = 4.4
	jet.gravity = Vector3(0.0, -8.0, 0.0)
	_fountain_fixed.add_child(jet)

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.85
	cylinder.height = 1.6
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.8, 0.0)
	add_child(shape)


func _build_pond() -> void:
	const WATER := Color(0.4, 0.68, 0.86)
	const LILY := Color(0.36, 0.66, 0.36)
	var water := Placeholder.part(self, Placeholder.cylinder(POND_RADIUS, 0.06), WATER, Vector3(0.0, 0.03, 0.0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# Камни по берегу и листья кувшинок.
	var rim := 22
	for i in rim:
		var angle := TAU * i / rim
		var pebble := Placeholder.part(self, Placeholder.sphere(rng.randf_range(0.2, 0.32)), STONE,
				Vector3(cos(angle), 0.0, sin(angle)) * (POND_RADIUS + 0.05) + Vector3(0.0, 0.08, 0.0))
		pebble.scale = Vector3(1.0, 0.6, 1.0)
	for i in 6:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(0.5, POND_RADIUS - 0.6)
		Placeholder.part(self, Placeholder.cylinder(rng.randf_range(0.22, 0.34), 0.03), LILY,
				Vector3(cos(angle) * distance, 0.08, sin(angle) * distance))
	Placeholder.part(self, Placeholder.sphere(0.09), Color(1.0, 0.7, 0.8), Vector3(0.6, 0.16, -0.4))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = POND_RADIUS
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.5, 0.0)
	add_child(shape)


func _add_box_collision(box_size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = center
	add_child(shape)
