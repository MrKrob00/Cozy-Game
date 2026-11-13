class_name PlotProp
extends StaticBody3D
## Крупный объект участка: дом, мастерская, скамейка, дерево, колодец.
## Ставит модель (готовую из assets/models или собранную из примитивов),
## коллизию и убирает траву под собой.

enum Kind { HOUSE, SHED, BENCH, TREE, WELL, FOUNTAIN, POND }

@export var kind := Kind.TREE
## Модель дома (assets/models): house_a … house_d.
@export var house_model := "house_a"
## Колодец с синей крышей (иначе с жёлтой).
@export var blue_roof := false
## Дерево с яблоками.
@export var fruit := false

const WOOD := Color(0.72, 0.52, 0.34)
const WOOD_DARK := Color(0.52, 0.36, 0.24)
const GLASS := Color(0.62, 0.84, 0.94)
const STONE := Color(0.70, 0.70, 0.72)
const GOLD := Color(1.0, 0.80, 0.25)
const LEAVES := Color(0.34, 0.66, 0.34)
const LEAVES_LIGHT := Color(0.44, 0.74, 0.36)


## Масштаб готовых моделей: дом около 4,5 м в ширину и 5,5 м в высоту.
const MODEL_SCALE := {"house_a": 5.8, "house_c": 5.8, "house_b": 4.6, "house_d": 4.6,
		"blacksmith": 2.5, "well": 2.7, "well_blue": 2.7}
const POND_RADIUS := 2.8
## Насколько растворяется крона, когда заслоняет игрока.
const CROWN_FADE := 0.3
## Масштаб модели дерева: крона около 2,5 м в поперечнике, высота около 5 м.
const TREE_SCALE := 4.2

## Размер модели по земле (X, Z) и её высота, метры.
var _footprint := Vector2.ZERO
var _height := 0.0
## Дым из трубы и фонарь у двери: появляются, когда участок выкошен.
var _smoke: CPUParticles3D
var _lantern: MeshInstance3D
var _lit := false
## Засов с замком перед мастерской, пока она заперта.
var _barrier: Node3D
var _padlock: MeshInstance3D
var _crown: Node3D
var _fade_material: ShaderMaterial
var _crown_fade := 1.0
# Части фонтана, которые меняются после починки.
var _fountain_broken: Node3D
var _fountain_fixed: Node3D


func _enter_tree() -> void:
	add_to_group("grass_shaper")
	add_to_group("plot_light")


## Дом оживает (вызывается, когда участок выкошен): из трубы идёт дым,
## у двери загорается фонарь.
func light_up() -> void:
	if _lit or kind != Kind.HOUSE:
		return
	_lit = true
	if _smoke:
		_smoke.emitting = true
	if _lantern:
		_lantern.visible = true


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
		Kind.HOUSE, Kind.SHED:
			field.block_rect(global_position, _model_footprint(), global_rotation.y)
		Kind.BENCH:
			field.block_rect(global_position, Vector2(1.6, 0.7), global_rotation.y)
		Kind.TREE:
			field.block_circle(global_position, 0.45)
		Kind.WELL:
			field.block_circle(global_position, 1.0)
		Kind.FOUNTAIN:
			field.block_circle(global_position, 2.0)
		Kind.POND:
			field.block_circle(global_position, POND_RADIUS + 0.25)


## Ширина постройки (вдоль её X), метры.
func get_width() -> float:
	return _model_footprint().x


# Имя готовой модели для этого объекта.
func _model_name() -> String:
	match kind:
		Kind.HOUSE:
			return house_model
		Kind.SHED:
			return "blacksmith"
		Kind.WELL:
			return "well_blue" if blue_roof else "well"
	return ""


# Размер готовой модели по земле (нужен траве раньше, чем модель поставлена).
func _model_footprint() -> Vector2:
	if _footprint == Vector2.ZERO:
		var model := _model_name()
		var box := Models.mesh(model).get_aabb()
		var scale_factor: float = MODEL_SCALE[model]
		_footprint = Vector2(box.size.x, box.size.z) * scale_factor
		_height = box.size.y * scale_factor
	return _footprint


# Ставит готовую модель и коллизию-коробку по её размеру.
func _place_model() -> MeshInstance3D:
	var model := _model_name()
	var footprint := _model_footprint()
	var instance := Models.place(self, model, Vector3.ZERO, MODEL_SCALE[model])
	var center: Vector3 = instance.mesh.get_aabb().get_center() * (MODEL_SCALE[model] as float)
	_add_box_collision(Vector3(footprint.x, _height, footprint.y), Vector3(center.x, _height * 0.5, center.z))
	return instance


# Дом — модель KayKit. Фасад смотрит на +Z.
func _build_house() -> void:
	var instance := _place_model()
	var top: Vector3 = _highest_point(instance.mesh) * (MODEL_SCALE[house_model] as float)
	_smoke = _make_smoke(top + Vector3(0.0, 0.1, 0.0))
	_lantern = Models.place(self, "lantern", Vector3(_footprint.x * 0.5 - 0.3, 0.0, _footprint.y * 0.5 + 0.35),
			0.75, 0.0)
	_lantern.set_meta("no_bake", true)
	_lantern.visible = false


# Мастерская — кузница KayKit. Пока она заперта, перед входом засов с замком.
func _build_shed() -> void:
	var instance := _place_model()
	var top: Vector3 = _highest_point(instance.mesh) * (MODEL_SCALE["blacksmith"] as float)
	_smoke = _make_smoke(top + Vector3(0.0, 0.1, 0.0))
	_barrier = Node3D.new()
	_barrier.position = Vector3(0.0, 0.0, _footprint.y * 0.5 + 0.25)
	_barrier.add_to_group("shadow_dynamic")
	add_child(_barrier)
	for side: float in [-1.0, 1.0]:
		Placeholder.part(_barrier, Placeholder.box(Vector3(0.14, 1.0, 0.14)), WOOD_DARK, Vector3(0.9 * side, 0.5, 0.0))
	for height: float in [0.45, 0.8]:
		Placeholder.part(_barrier, Placeholder.box(Vector3(1.9, 0.12, 0.08)), WOOD, Vector3(0.0, height, 0.0))
	_padlock = Placeholder.part(_barrier, Placeholder.box(Vector3(0.26, 0.26, 0.12)), GOLD, Vector3(0.0, 0.62, 0.08))
	_padlock.set_meta("no_bake", true)


## Отпирает мастерскую: засов с замком пропадает, из горна идёт дым.
func set_unlocked(animated: bool) -> void:
	if _barrier == null or not _barrier.visible:
		return
	_smoke.emitting = true
	if not animated:
		_barrier.visible = false
		return
	Juice.sparkle(self, _padlock.global_position)
	_padlock.visible = false
	var tween := create_tween()
	tween.tween_property(_barrier, "scale", Vector3.ONE * 0.01, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _barrier.visible = false)


# Самая высокая точка модели (труба): середина её верхних вершин.
func _highest_point(mesh: Mesh) -> Vector3:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -INF
	for vertex in vertices:
		top = maxf(top, vertex.y)
	var sum := Vector3.ZERO
	var count := 0
	for vertex in vertices:
		if vertex.y > top - 0.01:
			sum += vertex
			count += 1
	return sum / maxi(count, 1)


# Редкие облачка дыма из трубы.
func _make_smoke(at: Vector3) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = at
	smoke.emitting = false
	smoke.amount = 7
	smoke.lifetime = 3.2
	smoke.local_coords = false
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.22
	puff_mesh.height = 0.44
	puff_mesh.radial_segments = 6
	puff_mesh.rings = 3
	smoke.mesh = puff_mesh
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.vertex_color_use_as_albedo = true
	smoke.material_override = puff
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 0.98, 0.94, 0.0), Color(1.0, 0.98, 0.94, 0.75),
			Color(1.0, 0.98, 0.94, 0.0)])
	smoke.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.7))
	smoke.scale_amount_curve = grow
	smoke.direction = Vector3(0.25, 1.0, -0.1)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.8
	smoke.gravity = Vector3(0.0, 0.15, 0.0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	return smoke


# Колодец — модель KayKit.
func _build_well() -> void:
	var model := _model_name()
	Models.place(self, model, Vector3.ZERO, MODEL_SCALE[model])
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.95
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
	# Дерево — модель KayKit целиком в узле кроны: оно растворяется, когда
	# заслоняет игрока.
	_crown = Node3D.new()
	_crown.name = "Crown"
	add_child(_crown)
	Models.place(_crown, "tree_round", Vector3.ZERO, TREE_SCALE, hash(name) % 628 / 100.0)
	if fruit:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name)
		for i in 10:
			var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.7),
					rng.randf_range(-1.0, 1.0)).normalized()
			Placeholder.part(_crown, Placeholder.sphere(0.16, 6), Color(0.92, 0.26, 0.24),
					Vector3(0.0, 3.0, 0.0) + direction * Vector3(1.25, 1.1, 1.25))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.4
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(shape)


# Крона заслоняет игрока, если стоит между ним и камерой: тогда она растворяется
# точками. Материал с растворением (в нём discard, а он на телефоне выключает
# раннее отсечение скрытых пикселей) ставится только на время растворения.
func _update_crown_fade(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if camera == null or player == null or _crown == null:
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
	if _fade_material == null:
		_fade_material = Placeholder.fade_material()
	_fade_material.set_shader_parameter("fade", _crown_fade)
	var solid := is_equal_approx(_crown_fade, 1.0)
	for child in _crown.get_children():
		if child is MeshInstance3D and child.material_override in [_fade_material, Placeholder.vertex_material()]:
			child.material_override = Placeholder.vertex_material() if solid else _fade_material


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
	# Кувшинки — модели KayKit.
	for i in 6:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(0.5, POND_RADIUS - 0.6)
		Models.place(self, "waterlily_a" if i % 2 == 0 else "waterlily_b",
				Vector3(cos(angle) * distance, 0.07, sin(angle) * distance), rng.randf_range(3.5, 5.0),
				rng.randf() * TAU, false)
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
