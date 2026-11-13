class_name MowField
extends Node3D
## Поле с травой.
##
## Хранит маску покоса — сетку ячеек, по которой рисуется трава,
## считается процент и количество срезанной травы. Маска — единственный
## источник правды: шейдеры травы и земли только читают её.
##
## Объекты участка формируют траву до её создания: узлы из группы
## «grass_shaper» получают вызов shape_grass(field) и через block_*,
## pave_* и grow_tall_* помечают ячейки.

signal progress_changed(ratio: float)

const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

## Детализация травы: ближе LOD_NEAR метров от игрока рисуются все пучки,
## дальше LOD_FAR — только доля LOD_FAR_SHARE.
const LOD_NEAR := 12.0
const LOD_FAR := 30.0
const LOD_FAR_SHARE := 0.35
const LOD_INTERVAL := 0.25
## Байтов на ячейку: высота, тон полосы, «голая» ячейка.
const CHANNELS := 3
## Высота травы в маске (0–255): отросшая короткая, обычная, высокая и бурьян.
const HEIGHT_SHORT := 77
const HEIGHT_NORMAL := 153
const HEIGHT_TALL := 204
const HEIGHT_WEED := 255
const TONE_NEUTRAL := 128
## Значения _blocked: ячейка занята, земля в ней голая или под газоном.
const BLOCKED_BARE := 1
const BLOCKED_LAWN := 2

## Размер поля в метрах (X, Z). Центр — в начале координат узла.
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
## Доля поля под высокой травой (примерно).
@export_range(0.0, 1.0) var tall_grass_amount := 0.35
## Цвет «голых» ячеек после покоса: земля во дворе, камень на площади.
@export var bare_color := Color(0.66, 0.54, 0.38)
@export var random_seed := 1

var _resolution := Vector2i.ZERO
var _data := PackedByteArray()
## Не ноль — в ячейке ничего не растёт (занята объектом), она не входит в процент.
var _blocked := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _dirty := false
var _mowable_cells := 0
var _cut_cells := 0
var _grass_material: ShaderMaterial
var _ground_material: ShaderMaterial
var _grass_nodes: Array[MultiMeshInstance3D] = []
var _lod_timer := 0.0


func _enter_tree() -> void:
	add_to_group("mow_field")


func _ready() -> void:
	_resolution = Vector2i(ceili(size.x / cell_size), ceili(size.y / cell_size))
	_build_mask()
	# Траву формируют только объекты того же участка (или сцены, если участка нет).
	var owner_node := get_parent()
	for shaper in get_tree().get_nodes_in_group("grass_shaper"):
		if owner_node == null or owner_node.is_ancestor_of(shaper):
			shaper.shape_grass(self)
	_finish_mask()
	_build_materials()
	_build_ground()
	_build_grass()
	Graphics.quality_changed.connect(_rebuild_grass)


func _process(delta: float) -> void:
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = LOD_INTERVAL
		_update_lod()
	if not _dirty:
		return
	_upload()
	progress_changed.emit(get_progress())


## Доля скошенной площади, 0–1.
func get_progress() -> float:
	return float(_cut_cells) / float(maxi(_mowable_cells, 1))


## Срезает траву под прямоугольником ножа и красит полосу.
## Возвращает количество срезанной травы в единицах мешка за м²:
## 0,5 — отросшая короткая, 1 — обычная, 2 — высокая, 3 — бурьян.
## Если cut_weeds выключен, бурьян остаётся нетронутым.
func mow(world_position: Vector3, forward: Vector3, width: float, length: float,
		cut_weeds := true) -> float:
	var center := _to_field(world_position)
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

	# Тон полосы считается в мировых координатах, чтобы не зависеть от поворота поля.
	var world_forward := Vector2(forward.x, forward.z).normalized()
	var tone := int(clampf(0.5 + 0.5 * world_forward.dot(stripe_axis.normalized()), 0.0, 1.0) * 255.0)
	var cell_area := cell_size * cell_size
	var units := 0.0

	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size - center
			if absf(p.dot(f)) > half_l or absf(p.dot(r)) > half_w:
				continue
			var cell := y * _resolution.x + x
			if _blocked[cell] != 0:
				continue
			var i := cell * CHANNELS
			var height := _data[i]
			if height > HEIGHT_TALL and not cut_weeds:
				continue
			if height > 0:
				_data[i] = 0
				_cut_cells += 1
				units += cell_area * _units_per_area(height)
				_dirty = true
			if _data[i + 1] != tone:
				_data[i + 1] = tone
				_dirty = true
	return units


func _units_per_area(height: int) -> float:
	if height > HEIGHT_TALL:
		return 3.0
	if height > HEIGHT_NORMAL:
		return 2.0
	if height < HEIGHT_NORMAL:
		return 0.5
	return 1.0


## Новый день: на скошенных местах отрастает короткая трава.
## Дорожки и другие «голые» ячейки остаются чистыми.
func regrow() -> void:
	_cut_cells = 0
	for cell in _blocked.size():
		if _blocked[cell] != 0:
			continue
		var i := cell * CHANNELS
		if _data[i] == 0 and _data[i + 2] == 0:
			_data[i] = HEIGHT_SHORT
			_data[i + 1] = TONE_NEUTRAL
		if _data[i] == 0:
			_cut_cells += 1
	_upload()
	progress_changed.emit(get_progress())


## Лежит ли точка в пределах поля.
func contains(world_position: Vector3) -> bool:
	return _cell_at(world_position) != -1


## Высота травы в точке, 0–1 (0 — скошено, занято объектом или вне поля).
func get_height_at(world_position: Vector3) -> float:
	var cell := _cell_at(world_position)
	if cell == -1:
		return 0.0
	return _data[cell * CHANNELS] / 255.0


## Ограничивает точку границами поля с запасом margin (в метрах).
func clamp_to_bounds(world_position: Vector3, margin: float) -> Vector3:
	var local := to_local(world_position)
	var half := size * 0.5 + Vector2(margin, margin)
	local.x = clampf(local.x, -half.x, half.x)
	local.z = clampf(local.z, -half.y, half.y)
	return to_global(local)


## Точка, вокруг которой трава приминается (обычно косилка).
func set_pusher_position(world_position: Vector3) -> void:
	_grass_material.set_shader_parameter("pusher_position", world_position)


## До max_count точек с нескошенной травой, равномерно по списку остатков.
func get_uncut_positions(max_count: int) -> PackedVector3Array:
	var cells := PackedInt32Array()
	for cell in _blocked.size():
		if _data[cell * CHANNELS] > 0:
			cells.append(cell)
	var result := PackedVector3Array()
	if cells.is_empty():
		return result
	var step := maxf(float(cells.size()) / max_count, 1.0)
	var at := step * 0.5
	while int(at) < cells.size() and result.size() < max_count:
		var cell := cells[int(at)]
		var p := _cell_center(cell % _resolution.x, cell / _resolution.x) - size * 0.5
		result.append(to_global(Vector3(p.x, 0.0, p.y)))
		at += step
	return result


## Состояние покоса для сохранения.
func get_state() -> PackedByteArray:
	return _data.compress(FileAccess.COMPRESSION_ZSTD)


## Восстанавливает покос из сохранения. Возвращает false, если данные не подходят.
func set_state(state: PackedByteArray) -> bool:
	var raw := state.decompress(_data.size(), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != _data.size():
		return false
	_cut_cells = 0
	for cell in _blocked.size():
		if _blocked[cell] != 0:
			continue
		var i := cell * CHANNELS
		# Трава не может стать выше, чем выросла изначально.
		_data[i] = mini(raw[i], _data[i])
		_data[i + 1] = raw[i + 1]
		if _data[i] == 0:
			_cut_cells += 1
	_upload()
	progress_changed.emit(get_progress())
	return true


# --- Формирование травы объектами участка (вызывается из shape_grass) ---

## В круге ничего не растёт: ствол дерева, столб. Если bare выключен,
## земля в круге выглядит как стриженый газон, а не как голая почва.
func block_circle(world_center: Vector3, radius: float, bare := true) -> void:
	for cell in _cells_in_circle(world_center, radius):
		_blocked[cell] = BLOCKED_BARE if bare else BLOCKED_LAWN


## В прямоугольнике ничего не растёт: скамейка, клумба, стена.
## yaw — поворот объекта в мире (global_rotation.y).
func block_rect(world_center: Vector3, rect_size: Vector2, yaw := 0.0) -> void:
	for cell in _cells_in_rect(world_center, rect_size, yaw - global_rotation.y):
		_blocked[cell] = BLOCKED_BARE


## Под травой в круге — не газон, а камень или земля: после покоса стерни не остаётся.
func pave_circle(world_center: Vector3, radius: float) -> void:
	for cell in _cells_in_circle(world_center, radius):
		_data[cell * CHANNELS + 2] = 255


## То же для прямоугольника: клумба, площадка.
func pave_rect(world_center: Vector3, rect_size: Vector2, yaw := 0.0) -> void:
	for cell in _cells_in_rect(world_center, rect_size, yaw - global_rotation.y):
		_data[cell * CHANNELS + 2] = 255


## В круге растёт высокая трава (чтобы спрятать находку). Бурьян не понижает.
func grow_tall_circle(world_center: Vector3, radius: float) -> void:
	for cell in _cells_in_circle(world_center, radius):
		_data[cell * CHANNELS] = maxi(_data[cell * CHANNELS], HEIGHT_TALL)


## В круге растёт бурьян: его берёт только нож второго уровня.
func grow_weeds_circle(world_center: Vector3, radius: float) -> void:
	for cell in _cells_in_circle(world_center, radius):
		_data[cell * CHANNELS] = HEIGHT_WEED


func grow_weeds_rect(world_center: Vector3, rect_size: Vector2, yaw := 0.0) -> void:
	for cell in _cells_in_rect(world_center, rect_size, yaw - global_rotation.y):
		_data[cell * CHANNELS] = HEIGHT_WEED


func _to_field(world_position: Vector3) -> Vector2:
	var local := to_local(world_position)
	return Vector2(local.x, local.z) + size * 0.5


func _cell_center(x: int, y: int) -> Vector2:
	return (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size


func _cell_at(world_position: Vector3) -> int:
	var cell := Vector2i((_to_field(world_position) / cell_size).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= _resolution.x or cell.y >= _resolution.y:
		return -1
	return cell.y * _resolution.x + cell.x


func _cells_in_circle(world_center: Vector3, radius: float) -> PackedInt32Array:
	var center := _to_field(world_center)
	var result := PackedInt32Array()
	var last := _resolution - Vector2i.ONE
	var extent := Vector2(radius, radius)
	var from := Vector2i(((center - extent) / cell_size).floor()).clamp(Vector2i.ZERO, last)
	var to := Vector2i(((center + extent) / cell_size).floor()).clamp(Vector2i.ZERO, last)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			if _cell_center(x, y).distance_to(center) <= radius:
				result.append(y * _resolution.x + x)
	return result


func _cells_in_rect(world_center: Vector3, rect_size: Vector2, yaw: float) -> PackedInt32Array:
	var center := _to_field(world_center)
	var result := PackedInt32Array()
	var axis_x := Vector2(cos(yaw), -sin(yaw))
	var axis_z := Vector2(sin(yaw), cos(yaw))
	var half := rect_size * 0.5
	var reach := half.length()
	var last := _resolution - Vector2i.ONE
	var extent := Vector2(reach, reach)
	var from := Vector2i(((center - extent) / cell_size).floor()).clamp(Vector2i.ZERO, last)
	var to := Vector2i(((center + extent) / cell_size).floor()).clamp(Vector2i.ZERO, last)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var p := _cell_center(x, y) - center
			if absf(p.dot(axis_x)) <= half.x and absf(p.dot(axis_z)) <= half.y:
				result.append(y * _resolution.x + x)
	return result


func _build_mask() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	# Порог подобран так, чтобы tall_grass_amount примерно совпадал с долей площади.
	var threshold := lerpf(0.55, -0.55, tall_grass_amount)

	var cells := _resolution.x * _resolution.y
	_data.resize(cells * CHANNELS)
	_blocked.resize(cells)
	_blocked.fill(0)
	for y in _resolution.y:
		for x in _resolution.x:
			var i := (y * _resolution.x + x) * CHANNELS
			var n := noise.get_noise_2d(x * cell_size, y * cell_size)
			_data[i] = HEIGHT_TALL if n > threshold else HEIGHT_NORMAL
			_data[i + 1] = TONE_NEUTRAL
			_data[i + 2] = 0


func _finish_mask() -> void:
	_mowable_cells = 0
	_cut_cells = 0
	for cell in _blocked.size():
		if _blocked[cell] != 0:
			_data[cell * CHANNELS] = 0
			_data[cell * CHANNELS + 2] = 255 if _blocked[cell] == BLOCKED_BARE else 0
		else:
			_mowable_cells += 1
	_image = Image.create_from_data(_resolution.x, _resolution.y, false, Image.FORMAT_RGB8, _data)
	_texture = ImageTexture.create_from_image(_image)


func _upload() -> void:
	_dirty = false
	_image.set_data(_resolution.x, _resolution.y, false, Image.FORMAT_RGB8, _data)
	_texture.update(_image)


func _build_materials() -> void:
	var axis_x := global_basis.x
	var axis_z := global_basis.z
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	Graphics.track(_grass_material, true)
	Graphics.track(_ground_material, true)
	for mat: ShaderMaterial in [_grass_material, _ground_material]:
		mat.set_shader_parameter("mow_mask", _texture)
		mat.set_shader_parameter("field_center", Vector2(global_position.x, global_position.z))
		mat.set_shader_parameter("field_x", Vector2(axis_x.x, axis_x.z).normalized())
		mat.set_shader_parameter("field_z", Vector2(axis_z.x, axis_z.z).normalized())
		mat.set_shader_parameter("field_size", size)
	_ground_material.set_shader_parameter("bare_color", bare_color)
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


# Качество графики сменилось: пучки травы создаются заново с новой плотностью.
func _rebuild_grass() -> void:
	for node in _grass_nodes:
		node.free()
	_grass_nodes.clear()
	_build_grass()


func _build_grass() -> void:
	var quality := Graphics.preset
	_grass_material.set_shader_parameter("stubble", quality["stubble"])
	var clump := _create_clump_mesh(quality["blade_width"], quality["blades"])
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var spacing := 1.0 / sqrt(density * quality["grass_density"])
	var chunks := Vector2i(ceili(size.x / chunk_size), ceili(size.y / chunk_size))

	for cy in chunks.y:
		for cx in chunks.x:
			var origin := Vector2(cx, cy) * chunk_size
			var extent := Vector2(
					minf(chunk_size, size.x - origin.x),
					minf(chunk_size, size.y - origin.y))
			var cols := maxi(int(extent.x / spacing), 1)
			var rows := maxi(int(extent.y / spacing), 1)

			var transforms: Array[Transform3D] = []
			for gy in rows:
				for gx in cols:
					var px := (gx + rng.randf()) * extent.x / cols
					var pz := (gy + rng.randf()) * extent.y / rows
					var s := rng.randf_range(0.85, 1.2)
					var turn := Basis(Vector3.UP, rng.randf() * TAU).scaled(
							Vector3(s, rng.randf_range(0.85, 1.1), s))
					var cell := Vector2i(((origin + Vector2(px, pz)) / cell_size).floor())
					cell = cell.clamp(Vector2i.ZERO, _resolution - Vector2i.ONE)
					if _blocked[cell.y * _resolution.x + cell.x] != 0:
						continue
					transforms.append(Transform3D(turn, Vector3(px, 0.0, pz)))
			if transforms.is_empty():
				continue
			# Пучки перемешаны: тогда первые N из них — равномерная выборка по куску,
			# и вдали можно рисовать только часть (visible_instance_count).
			_shuffle(transforms, rng)

			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_custom_data = true
			multimesh.mesh = clump
			multimesh.instance_count = transforms.size()
			for index in transforms.size():
				multimesh.set_instance_transform(index, transforms[index])
				multimesh.set_instance_custom_data(index, Color(rng.randf(), 0.0, 0.0, 0.0))

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
			_grass_nodes.append(instance)


# Тасование Фишера — Йейтса своим генератором: одинаково при каждом запуске.
func _shuffle(items: Array[Transform3D], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := items[i]
		items[i] = items[j]
		items[j] = swap


# Детализация травы: куски поля вдали от игрока рисуют часть пучков.
# Камера смотрит сверху-сбоку, поэтому дальние куски на экране мелкие.
func _update_lod() -> void:
	var focus := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if focus == null or player == null:
		return
	var at := Vector2(player.global_position.x, player.global_position.z)
	for instance in _grass_nodes:
		var box := instance.get_aabb()
		var corner := instance.global_position
		var rect := Rect2(Vector2(corner.x, corner.z), Vector2.ZERO)
		# Поле может быть повёрнуто: берём прямоугольник по углам куска.
		for x: float in [box.position.x, box.end.x]:
			for z: float in [box.position.z, box.end.z]:
				var world := instance.global_transform * Vector3(x, 0.0, z)
				rect = rect.expand(Vector2(world.x, world.z))
		var distance := at.distance_to(at.clamp(rect.position, rect.end))
		var share := lerpf(1.0, LOD_FAR_SHARE, clampf(inverse_lerp(LOD_NEAR, LOD_FAR, distance), 0.0, 1.0))
		var count := instance.multimesh.instance_count
		instance.multimesh.visible_instance_count = -1 if share >= 0.999 else maxi(int(count * share), 1)


## Пучок из трёх широких «мультяшных» травинок. UV.y — высота вдоль травинки.
## width_scale делает травинки шире, когда пучков меньше.
func _create_clump_mesh(width_scale := 1.0, blades := 3) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var blade_width := 0.11 * width_scale
	var spread := 0.07 * width_scale

	for b in blades:
		var angle := TAU * b / blades + 0.4
		var turn := Basis(Vector3.UP, angle)
		var lean := 0.12 + 0.05 * b
		var height := blade_height * (1.0 - 0.12 * b)
		var points := [
			Vector3(-blade_width * 0.5, 0.0, spread),
			Vector3(blade_width * 0.5, 0.0, spread),
			Vector3(-blade_width * 0.36, height * 0.55, spread + lean * 0.4),
			Vector3(blade_width * 0.36, height * 0.55, spread + lean * 0.4),
			Vector3(0.0, height, spread + lean),
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
