class_name MowField
extends Node3D
## Поляна с травой.
##
## Хранит маску покоса — сетку ячеек, по которой рисуется трава,
## считается процент и количество срезанной травы. Маска — единственный
## источник правды: шейдеры травы и земли только читают её.

signal progress_changed(ratio: float)

const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

## Высота обычной и высокой травы в маске (0–255).
const HEIGHT_NORMAL := 153
const HEIGHT_TALL := 255
const TONE_NEUTRAL := 128

## Размер поляны в метрах (X, Z). Центр — в начале координат узла.
@export var size := Vector2(24.0, 24.0)
## Размер ячейки маски в метрах.
@export var cell_size := 0.125
## Пучков травы на квадратный метр. Главная настройка качества.
@export_range(4.0, 80.0) var density := 36.0
@export var chunk_size := 8.0
## Высота пучка высокой травы в метрах.
@export var blade_height := 0.75
## Направление «от камеры»: проход вдоль него даёт светлую полосу.
@export var stripe_axis := Vector2(-1.0, -1.0)
## Доля поляны под высокой травой (примерно).
@export_range(0.0, 1.0) var tall_grass_amount := 0.35
@export var random_seed := 1

var _resolution := Vector2i.ZERO
var _data := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _dirty := false
var _total_cells := 0
var _cut_cells := 0
var _grass_material: ShaderMaterial
var _ground_material: ShaderMaterial


func _enter_tree() -> void:
	add_to_group("mow_field")


func _ready() -> void:
	_resolution = Vector2i(ceili(size.x / cell_size), ceili(size.y / cell_size))
	_build_mask()
	_build_materials()
	_build_ground()
	_build_grass()


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	_image.set_data(_resolution.x, _resolution.y, false, Image.FORMAT_RG8, _data)
	_texture.update(_image)
	progress_changed.emit(get_progress())


## Доля скошенной площади, 0–1.
func get_progress() -> float:
	return float(_cut_cells) / float(maxi(_total_cells, 1))


## Срезает траву под прямоугольником ножа и красит полосу.
## Возвращает количество срезанной травы в единицах мешка
## (1 ед. за м² обычной травы, 2 ед. за м² высокой).
func mow(world_position: Vector3, forward: Vector3, width: float, length: float) -> float:
	var local := to_local(world_position)
	var center := Vector2(local.x, local.z) + size * 0.5
	var local_forward := global_basis.inverse() * forward
	var f := Vector2(local_forward.x, local_forward.z).normalized()
	var r := Vector2(-f.y, f.x)
	var half_l := length * 0.5
	var half_w := width * 0.5

	var extent := Vector2(
			absf(f.x) * half_l + absf(r.x) * half_w,
			absf(f.y) * half_l + absf(r.y) * half_w)
	var last := _resolution - Vector2i.ONE
	var from := Vector2i(((center - extent) / cell_size).floor()).clamp(Vector2i.ZERO, last)
	var to := Vector2i(((center + extent) / cell_size).floor()).clamp(Vector2i.ZERO, last)

	var tone := int(clampf(0.5 + 0.5 * f.dot(stripe_axis.normalized()), 0.0, 1.0) * 255.0)
	var cell_area := cell_size * cell_size
	var units := 0.0

	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size - center
			if absf(p.dot(f)) > half_l or absf(p.dot(r)) > half_w:
				continue
			var i := (y * _resolution.x + x) * 2
			var height := _data[i]
			if height > 0:
				_data[i] = 0
				_cut_cells += 1
				units += cell_area * (2.0 if height > HEIGHT_NORMAL else 1.0)
				_dirty = true
			if _data[i + 1] != tone:
				_data[i + 1] = tone
				_dirty = true
	return units


## Высота травы в точке, 0–1 (0 — скошено или вне поляны).
func get_height_at(world_position: Vector3) -> float:
	var local := to_local(world_position)
	var cell := Vector2i(((Vector2(local.x, local.z) + size * 0.5) / cell_size).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= _resolution.x or cell.y >= _resolution.y:
		return 0.0
	return _data[(cell.y * _resolution.x + cell.x) * 2] / 255.0


## Ограничивает точку границами поляны с запасом margin (в метрах).
func clamp_to_bounds(world_position: Vector3, margin: float) -> Vector3:
	var local := to_local(world_position)
	var half := size * 0.5 + Vector2(margin, margin)
	local.x = clampf(local.x, -half.x, half.x)
	local.z = clampf(local.z, -half.y, half.y)
	return to_global(local)


## Точка, вокруг которой трава раздвигается (обычно косилка).
func set_pusher_position(world_position: Vector3) -> void:
	_grass_material.set_shader_parameter("pusher_position", world_position)


func _build_mask() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	# Порог подобран так, чтобы tall_grass_amount примерно совпадал с долей площади.
	var threshold := lerpf(0.55, -0.55, tall_grass_amount)

	_total_cells = _resolution.x * _resolution.y
	_cut_cells = 0
	_data.resize(_total_cells * 2)
	for y in _resolution.y:
		for x in _resolution.x:
			var i := (y * _resolution.x + x) * 2
			var n := noise.get_noise_2d(x * cell_size, y * cell_size)
			_data[i] = HEIGHT_TALL if n > threshold else HEIGHT_NORMAL
			_data[i + 1] = TONE_NEUTRAL

	_image = Image.create_from_data(_resolution.x, _resolution.y, false, Image.FORMAT_RG8, _data)
	_texture = ImageTexture.create_from_image(_image)


func _build_materials() -> void:
	var field_min := Vector2(global_position.x, global_position.z) - size * 0.5
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	for mat: ShaderMaterial in [_grass_material, _ground_material]:
		mat.set_shader_parameter("mow_mask", _texture)
		mat.set_shader_parameter("field_min", field_min)
		mat.set_shader_parameter("field_size", size)
	_grass_material.set_shader_parameter("pusher_position", Vector3(0.0, -100.0, 0.0))


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = _ground_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


func _build_grass() -> void:
	var clump := _create_clump_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var spacing := 1.0 / sqrt(density)
	var chunks := Vector2i(ceili(size.x / chunk_size), ceili(size.y / chunk_size))

	for cy in chunks.y:
		for cx in chunks.x:
			var origin := Vector2(cx, cy) * chunk_size
			var extent := Vector2(
					minf(chunk_size, size.x - origin.x),
					minf(chunk_size, size.y - origin.y))
			var cols := maxi(int(extent.x / spacing), 1)
			var rows := maxi(int(extent.y / spacing), 1)

			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_custom_data = true
			multimesh.mesh = clump
			multimesh.instance_count = cols * rows

			var index := 0
			for gy in rows:
				for gx in cols:
					var px := (gx + rng.randf()) * extent.x / cols
					var pz := (gy + rng.randf()) * extent.y / rows
					var s := rng.randf_range(0.85, 1.2)
					var turn := Basis(Vector3.UP, rng.randf() * TAU).scaled(
							Vector3(s, rng.randf_range(0.85, 1.1), s))
					multimesh.set_instance_transform(index, Transform3D(turn, Vector3(px, 0.0, pz)))
					multimesh.set_instance_custom_data(index, Color(rng.randf(), 0.0, 0.0, 0.0))
					index += 1

			var instance := MultiMeshInstance3D.new()
			instance.name = "Grass_%d_%d" % [cx, cy]
			instance.multimesh = multimesh
			instance.material_override = _grass_material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.position = Vector3(origin.x - size.x * 0.5, 0.0, origin.y - size.y * 0.5)
			instance.custom_aabb = AABB(
					Vector3(-0.5, 0.0, -0.5),
					Vector3(extent.x + 1.0, blade_height * 1.3, extent.y + 1.0))
			add_child(instance)


## Пучок из трёх широких «мультяшных» травинок. UV.y — высота вдоль травинки.
func _create_clump_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const BLADES := 3
	const WIDTH := 0.11
	const SPREAD := 0.07

	for b in BLADES:
		var angle := TAU * b / BLADES + 0.4
		var turn := Basis(Vector3.UP, angle)
		var lean := 0.12 + 0.05 * b
		var height := blade_height * (1.0 - 0.12 * b)
		var points := [
			Vector3(-WIDTH * 0.5, 0.0, SPREAD),
			Vector3(WIDTH * 0.5, 0.0, SPREAD),
			Vector3(-WIDTH * 0.36, height * 0.55, SPREAD + lean * 0.4),
			Vector3(WIDTH * 0.36, height * 0.55, SPREAD + lean * 0.4),
			Vector3(0.0, height, SPREAD + lean),
		]
		var start := vertices.size()
		for point: Vector3 in points:
			vertices.append(turn * point)
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.5, point.y / blade_height))
		for offset: int in [0, 1, 3, 0, 3, 2, 2, 3, 4]:
			indices.append(start + offset)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
