class_name Meadow
## Земля вокруг участков: не одна заливка, а луг.
##
## Приёмы из разборов стилизованного low-poly (Alba, Firewatch, статьи 80.lv):
##   * зоны почвы вместо одного цвета: светлая и тёмная трава, клевер,
##     вытоптанная земля у дороги — цвет в вершинах, без текстур и без
##     лишней работы на пиксель;
##   * россыпи группами разного размера со случайным поворотом и масштабом;
##   * цветы как яркие акценты;
##   * густые кочки вдоль заборов, чтобы сломать длинные прямые линии.
## Всё временное, из примитивов; россыпи склеиваются по клеткам (Placeholder).

const GRASS_LIGHT := Color(0.50, 0.73, 0.33)
const GRASS_DARK := Color(0.30, 0.54, 0.29)
const CLOVER := Color(0.62, 0.74, 0.30)
const DRY := Color(0.74, 0.70, 0.38)
const SLOPE := Color(0.50, 0.58, 0.32)
const DIRT := Color(0.60, 0.47, 0.32)
const WORN := Color(0.56, 0.60, 0.36)
const ROAD := Color(0.84, 0.70, 0.48)
const ROAD_RUT := Color(0.68, 0.53, 0.36)
const ROAD_EDGE := Color(0.60, 0.58, 0.36)
const TUFTS := [Color(0.40, 0.66, 0.32), Color(0.52, 0.76, 0.36), Color(0.34, 0.58, 0.32),
		Color(0.66, 0.76, 0.38)]
const PETALS := [Color(1.0, 0.98, 0.94), Color(1.0, 0.86, 0.32), Color(1.0, 0.58, 0.68),
		Color(0.74, 0.62, 1.0), Color(1.0, 0.64, 0.34)]
const ROCKS := [Color(0.66, 0.66, 0.68), Color(0.58, 0.58, 0.62), Color(0.74, 0.72, 0.68)]
const STEM := Color(0.32, 0.58, 0.30)
const MUSHROOM_CAP := Color(0.90, 0.32, 0.26)
const MUSHROOM_STEM := Color(0.98, 0.94, 0.86)

## Шаг сетки земли, метры, и размер одного куска (кусок — отдельная модель,
## чтобы невидимые отсекались).
const GRID_STEP := 2.0
## Насколько нарисованная дорога шире той, по которой ходит игрок.
const ROAD_GROW := 0.9
const TILE := 30.0


## Земля луга: сетка с цветом в вершинах, кусками по TILE метров.
static func build_ground(parent: Node3D, area: Rect2, seed: int, terrain: Terrain) -> void:
	var noise := _noise(seed, 0.06)
	var patches := _noise(seed + 1, 0.13)
	var spots := _noise(seed + 2, 0.2)
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.y
		while z < area.end.y:
			var tile := Rect2(x, z, minf(TILE, area.end.x - x), minf(TILE, area.end.y - z))
			_ground_tile(parent, tile, noise, patches, spots, terrain)
			z += TILE
		x += TILE


## Цвет земли в точке: зоны травы, клевер, плешки земли, вытоптанное у дороги.
static func ground_color(at: Vector2, terrain: Terrain, noise: FastNoiseLite,
		patches: FastNoiseLite, spots: FastNoiseLite) -> Color:
	# Крупные пятна светлой и тёмной травы с чёткой, но мягкой границей.
	var big := noise.get_noise_2dv(at)
	var color := GRASS_DARK.lerp(GRASS_LIGHT, smoothstep(-0.25, 0.2, big))
	color = color.lerp(DRY, smoothstep(0.35, 0.6, big) * 0.6)
	color = color.lerp(CLOVER, smoothstep(0.25, 0.45, patches.get_noise_2dv(at)) * 0.75)
	color = color.lerp(DIRT, smoothstep(0.42, 0.6, spots.get_noise_2dv(at)) * 0.85)
	var to_road := -terrain.road_depth(at, ROAD_GROW)
	color = color.lerp(WORN, clampf(1.0 - to_road / 1.8, 0.0, 1.0) * 0.65)
	return color


## Дороги: одна сетка на всю сеть дорог (на перекрёстках ничего не
## накладывается), с колеями, крапинами и рваными краями.
static func build_roads(parent: Node3D, seed: int, terrain: Terrain) -> void:
	const STEP := 0.8
	var noise := _noise(seed + 3, 0.6)
	var area := Rect2()
	for rect in terrain.road_rects():
		area = rect if area.size == Vector2.ZERO else area.merge(rect)
	area = area.grow(ROAD_GROW + STEP)
	var columns := int(area.size.x / STEP) + 1
	var rows := int(area.size.y / STEP) + 1
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# Вершина создаётся один раз на узел сетки: соседние клетки делят её.
	var vertex_at: Dictionary = {}
	var vertex := func(column: int, row: int) -> int:
		var key := Vector2i(column, row)
		if vertex_at.has(key):
			return vertex_at[key]
		var at := area.position + Vector2(column, row) * STEP
		var depth := terrain.road_depth(at, ROAD_GROW)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key) + seed
		var height := terrain.height_at(at) + 0.03
		# Края дороги неровные: крайние вершины гуляют в стороны.
		if depth < STEP * 0.75:
			at += Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		# Две колеи идут на постоянном расстоянии от края.
		var rut := _bump(depth, 1.7, 0.32)
		var color := ROAD.lerp(ROAD_RUT, rut * 0.8)
		color = color.lerp(ROAD_RUT, maxf(noise.get_noise_2dv(at), 0.0) * 0.5)
		color = color.lerp(ROAD_EDGE, 1.0 - smoothstep(0.0, 0.7, depth))
		vertices.append(Vector3(at.x, height, at.y))
		colors.append(color)
		vertex_at[key] = vertices.size() - 1
		return vertices.size() - 1
	for row in rows:
		for column in columns:
			var center := area.position + (Vector2(column, row) + Vector2(0.5, 0.5)) * STEP
			if terrain.road_depth(center, ROAD_GROW) < 0.0:
				continue
			var a: int = vertex.call(column, row)
			var b: int = vertex.call(column + 1, row)
			var c: int = vertex.call(column, row + 1)
			var d: int = vertex.call(column + 1, row + 1)
			indices.append_array([a, b, c, c, b, d])
	_add_mesh(parent, "Roads", vertices, colors, indices)


## Россыпи: кочки, цветы, камни, грибы. free_at(точка) говорит, можно ли там.
static func scatter(parent: Node3D, area: Rect2, free_at: Callable, trees: Array[Vector3], seed: int,
		terrain: Terrain) -> void:
	var on_ground := func(at: Vector2) -> Vector3:
		return Vector3(at.x, terrain.height_at(at), at.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lush := _noise(seed + 4, 0.06)
	# На низком качестве россыпей меньше: это треугольники на каждом кадре.
	var amount: float = Graphics.preset["scatter"]
	# Кочки: гуще там, где трава сочнее.
	for i in int(area.get_area() * 0.09 * amount):
		var at := _random_point(area, rng)
		if lush.get_noise_2dv(at) < -0.15 or not free_at.call(at):
			continue
		tuft(parent, on_ground.call(at), rng)
	# Цветы куртинами, у каждой свой цвет.
	for i in int(area.get_area() / 40.0 * amount):
		var at := _random_point(area, rng)
		if not free_at.call(at):
			continue
		var petal: Color = PETALS[rng.randi() % PETALS.size()]
		for k in rng.randi_range(4, 9):
			var spot := at + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			if free_at.call(spot):
				flower(parent, on_ground.call(spot), petal, rng)
	# Камни группами: большой, средний и мелкие рядом.
	for i in int(area.get_area() / 260.0):
		var at := _random_point(area, rng)
		if not free_at.call(at):
			continue
		var size := rng.randf_range(0.22, 0.38)
		for k in rng.randi_range(1, 3):
			var spot := at + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
			rock(parent, on_ground.call(spot), size, rng)
			size *= rng.randf_range(0.45, 0.7)
	# Грибы у стволов деревьев.
	for tree in trees:
		if rng.randf() > 0.55:
			continue
		var angle := rng.randf() * TAU
		var spot := Vector2(tree.x, tree.z) + Vector2(cos(angle), sin(angle)) * rng.randf_range(0.9, 1.8)
		if free_at.call(spot):
			for k in rng.randi_range(1, 3):
				mushroom(parent, on_ground.call(spot + Vector2(rng.randf_range(-0.3, 0.3),
						rng.randf_range(-0.3, 0.3))), rng)


## Кочки и цветы вдоль линии (забор): ломают длинную прямую.
static func line_clumps(parent: Node3D, from: Vector3, to: Vector3, free_at: Callable, seed: int,
		terrain: Terrain) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var length := from.distance_to(to)
	var side := (to - from).cross(Vector3.UP).normalized()
	var along := 0.0
	while along < length:
		var at := from.lerp(to, along / length) + side * rng.randf_range(-0.45, 0.45)
		at.y = terrain.height_at(Vector2(at.x, at.z))
		if free_at.call(Vector2(at.x, at.z)):
			if rng.randf() < 0.18:
				flower(parent, at, PETALS[rng.randi() % PETALS.size()], rng)
			else:
				tuft(parent, at, rng, rng.randf_range(1.0, 1.5))
		along += rng.randf_range(0.35, 0.9)


static func tuft(parent: Node3D, at: Vector3, rng: RandomNumberGenerator, size := 1.0) -> void:
	var color: Color = TUFTS[rng.randi() % TUFTS.size()]
	for k in rng.randi_range(2, 4):
		var height := rng.randf_range(0.28, 0.52) * size
		var blade := Placeholder.part(parent, Placeholder.cylinder(0.06 * size, height, 0.0, 3, false), color,
				at + Vector3(rng.randf_range(-0.1, 0.1), height * 0.5, rng.randf_range(-0.1, 0.1)),
				Vector3(rng.randf_range(-28.0, 28.0), rng.randf() * 360.0, rng.randf_range(-28.0, 28.0)))
		blade.set_meta("sway", 1.0)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func flower(parent: Node3D, at: Vector3, petal: Color, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(0.16, 0.3)
	var stem := Placeholder.part(parent, Placeholder.cylinder(0.015, height, 0.015, 3, false), STEM,
			at + Vector3(0.0, height * 0.5, 0.0))
	var head := Placeholder.part(parent, Placeholder.box(Vector3(0.16, 0.05, 0.16)), petal,
			at + Vector3(0.0, height, 0.0), Vector3(0.0, rng.randf() * 90.0, 0.0))
	for flower_part: MeshInstance3D in [stem, head]:
		flower_part.set_meta("sway", 0.8)
		flower_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func rock(parent: Node3D, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	# Камни — модели KayKit (их пять видов); size — примерный радиус.
	var model: String = ["rock_a", "rock_b", "rock_c", "rock_d", "rock_e"][rng.randi() % 5]
	Models.place(parent, model, at, size * 9.0, rng.randf() * TAU)


static func mushroom(parent: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var size := rng.randf_range(0.7, 1.2)
	Placeholder.part(parent, Placeholder.cylinder(0.035 * size, 0.14 * size, 0.03 * size, 5), MUSHROOM_STEM,
			at + Vector3(0.0, 0.07 * size, 0.0))
	var cap := Placeholder.part(parent, Placeholder.sphere(0.09 * size, 6), MUSHROOM_CAP,
			at + Vector3(0.0, 0.15 * size, 0.0))
	cap.scale = Vector3(1.0, 0.6, 1.0)


static func _ground_tile(parent: Node3D, tile: Rect2, noise: FastNoiseLite,
		patches: FastNoiseLite, spots: FastNoiseLite, terrain: Terrain) -> void:
	var columns := maxi(int(ceilf(tile.size.x / GRID_STEP)), 1)
	var rows := maxi(int(ceilf(tile.size.y / GRID_STEP)), 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for row in rows + 1:
		for column in columns + 1:
			var at := tile.position + Vector2(column * tile.size.x / columns, row * tile.size.y / rows)
			# Под дорогой земля чуть ниже: на подъёмах сетка земли редкая
			# и иначе прорезала бы дорогу.
			var sink := 0.22 if terrain.road_depth(at, ROAD_GROW + GRID_STEP) > 0.0 else 0.03
			vertices.append(Vector3(at.x, terrain.height_at(at) - sink, at.y))
			normals.append(terrain.normal_at(at))
			var color := ground_color(at, terrain, noise, patches, spots)
			# Склоны чуть темнее и теплее: рельеф читается сверху.
			var slope := 1.0 - normals[-1].y
			color = color.lerp(SLOPE, clampf(slope * 4.0, 0.0, 0.45))
			colors.append(color)
	for row in rows:
		for column in columns:
			var a := row * (columns + 1) + column
			var b := a + columns + 1
			indices.append_array([a, a + 1, b, b, a + 1, b + 1])
	_add_mesh(parent, "Ground_%d_%d" % [int(tile.position.x), int(tile.position.y)], vertices, colors, indices,
			normals)


static func _add_mesh(parent: Node3D, mesh_name: String, vertices: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array, normals := PackedVector3Array()) -> void:
	if normals.is_empty():
		normals.resize(vertices.size())
		normals.fill(Vector3.UP)
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = Placeholder.vertex_material(true)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _noise(seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	return noise


static func _random_point(area: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))


static func _bump(value: float, center: float, width: float) -> float:
	var d := (value - center) / width
	return exp(-d * d)
