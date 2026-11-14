class_name Placeholder
## Временные модели из примитивов с мультяшным материалом.
## Заменяются настоящими моделями, когда они появятся.
##
## Детали создаются по одной (part), а потом склеиваются: bake_tree собирает
## неподвижные детали каждого узла в одну модель с цветом в вершинах. Вместо
## десятков вызовов отрисовки на объект остаётся один.
##
## Отметки (meta) на узлах:
##   no_bake    — деталь не склеивать: её двигают или меняют отдельно;
##   merge_up   — узел-контейнер: его детали склеиваются вместе с родителем;
##   bake_cell  — у узла: склеивать по клеткам такого размера (метры), чтобы
##                не терять отсечение невидимого на больших площадях;
##   plant      — у узла: склеенные детали — цветы (качаются, приминаются);
##   anchor     — у детали цветка: основание стебля в координатах узла;
##   sway       — у детали: сила качания на ветру (0..1), пишется в альфу цвета.

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const RECEIVE_SHADER := preload("res://shaders/toon_receive.gdshader")
const FADE_SHADER := preload("res://shaders/toon_fade.gdshader")
const PLANT_SHADER := preload("res://shaders/toon_plant.gdshader")

static var _materials: Dictionary = {}
static var _receive_materials: Dictionary = {}
## Цвет детали по её материалу (для склейки).
static var _colors: Dictionary = {}
static var _vertex_material: ShaderMaterial
static var _vertex_receive_material: ShaderMaterial
static var _plant_material: ShaderMaterial


static func material(color: Color) -> ShaderMaterial:
	if _materials.has(color):
		return _materials[color]
	var mat := _make(TOON_SHADER, color)
	_materials[color] = mat
	_colors[mat] = color
	return mat


## Материал плоской поверхности, которая принимает тени предметов.
static func ground_material(color: Color) -> ShaderMaterial:
	if _receive_materials.has(color):
		return _receive_materials[color]
	var mat := _make(RECEIVE_SHADER, color, true)
	_receive_materials[color] = mat
	_colors[mat] = color
	return mat


## Общий материал склеенных моделей: цвет берётся из вершин.
static func vertex_material(receives := false) -> ShaderMaterial:
	if receives:
		if _vertex_receive_material == null:
			_vertex_receive_material = _make(RECEIVE_SHADER, Color.WHITE, true)
		return _vertex_receive_material
	if _vertex_material == null:
		_vertex_material = _make(TOON_SHADER, Color.WHITE)
		_vertex_material.set_shader_parameter("sway_strength", 1.0)
	return _vertex_material


## Общий материал цветов; косилку для него ставит игрок (set_pusher).
static func plant_material() -> ShaderMaterial:
	if _plant_material == null:
		_plant_material = _make(PLANT_SHADER, Color.WHITE)
	return _plant_material


## Новый материал растворения для одной модели (крона дерева).
static func fade_material() -> ShaderMaterial:
	var mat := _make(FADE_SHADER, Color.WHITE)
	mat.set_shader_parameter("sway_strength", 1.0)
	return mat


static func set_pusher(world_position: Vector3) -> void:
	plant_material().set_shader_parameter("pusher_position", world_position)


static func _make(shader: Shader, color: Color, receives := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo", color)
	# Земля, дороги и дорожки рисуются после моделей и травы: то, что ими
	# закрыто, не закрашивается зря.
	if receives:
		mat.render_priority = 1
	return Graphics.track(mat, receives)


static func part(parent: Node3D, mesh: Mesh, color: Color, position := Vector3.ZERO,
		rotation_degrees := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance


## Склеивает детали во всём поддереве root (включая сам root).
static func bake_tree(root: Node) -> void:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "Node3D", true, false))
	var baked := false
	for node in nodes:
		if node is Node3D and is_instance_valid(node) and not node.has_meta("merge_up"):
			baked = _bake_node(node) or baked
	if baked:
		Graphics.casters_changed.emit()


# Склеивает детали одного узла: прямых потомков и потомков контейнеров merge_up.
static func _bake_node(node: Node3D) -> bool:
	var parts: Array[MeshInstance3D] = []
	_collect(node, parts)
	if parts.is_empty():
		return false
	var cell: float = node.get_meta("bake_cell", 0.0)
	var plant: bool = node.has_meta("plant")
	# Группы: по клетке и по тому, отбрасывает ли деталь тень.
	var groups: Dictionary = {}
	var to_node := node.global_transform.affine_inverse()
	for mesh_part in parts:
		var local := to_node * mesh_part.global_transform
		var casts := mesh_part.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var key := [casts, Vector2i.ZERO]
		if cell > 0.0:
			key[1] = Vector2i((Vector2(local.origin.x, local.origin.z) / cell).floor())
		if not groups.has(key):
			groups[key] = []
		groups[key].append([mesh_part, local])
	for key: Array in groups:
		var mesh := _merge(groups[key], plant)
		var instance := MeshInstance3D.new()
		instance.name = "Baked_%d_%d" % [key[1].x, key[1].y] + ("_cast" if key[0] else "")
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if plant:
			instance.material_override = plant_material()
		else:
			# Плоские детали (дорожки, земля клумбы) принимают тени, объёмные их отбрасывают.
			instance.material_override = vertex_material(not key[0])
		node.add_child(instance)
		if key[0]:
			instance.add_to_group("shadow_caster")
	for mesh_part in parts:
		mesh_part.get_parent().remove_child(mesh_part)
		mesh_part.queue_free()
	return true


static func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and _bakeable(child):
			into.append(child)
		elif child is Node3D and child.has_meta("merge_up"):
			_collect(child, into)


static func _bakeable(part_mesh: MeshInstance3D) -> bool:
	return part_mesh.visible and part_mesh.mesh != null and not part_mesh.has_meta("no_bake") \
			and (_colors.has(part_mesh.material_override) or part_mesh.has_meta("vertex_colors"))


# Одна модель из деталей: вершины в координатах узла, цвет детали в вершинах
# (в sRGB: движок переводит его в линейный сам), у цветов — основание стебля в UV2.
static func _merge(items: Array, plant: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	# UV.y — низ детали (её «земля»): от него тень ложится на землю. Окружение
	# склеено клетками, и детали в одной модели стоят на разной высоте.
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for item: Array in items:
		var mesh_part: MeshInstance3D = item[0]
		var local: Transform3D = item[1]
		var arrays: Array = mesh_part.mesh.get_mesh_arrays() if mesh_part.mesh is PrimitiveMesh \
				else mesh_part.mesh.surface_get_arrays(0)
		var part_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var part_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var part_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var start := vertices.size()
		var placed := local * part_vertices
		vertices.append_array(placed)
		var bottom := INF
		for vertex in placed:
			bottom = minf(bottom, vertex.y)
		var part_uv := PackedVector2Array()
		part_uv.resize(placed.size())
		part_uv.fill(Vector2(0.0, bottom))
		uv.append_array(part_uv)
		var normal_basis := Transform3D(local.basis.inverse().transposed(), Vector3.ZERO)
		normals.append_array(normal_basis * part_normals)
		if mesh_part.has_meta("vertex_colors"):
			# Готовая модель: цвета уже в вершинах, альфа — качание.
			colors.append_array(arrays[Mesh.ARRAY_COLOR])
		else:
			# Цвет вершины пишется как есть, в sRGB: движок сам переводит цвета
			# вершин в линейные (проверено замером: с переводом здесь модели
			# получались вдвое темнее).
			var color: Color = _colors[mesh_part.material_override]
			# Альфа цвета вершины — сила качания на ветру (листва, кочки, цветы).
			color.a = mesh_part.get_meta("sway", 0.0)
			var part_colors := PackedColorArray()
			part_colors.resize(part_vertices.size())
			part_colors.fill(color)
			colors.append_array(part_colors)
		if plant:
			var anchor: Vector3 = mesh_part.get_meta("anchor", local.origin)
			var part_uv2 := PackedVector2Array()
			part_uv2.resize(part_vertices.size())
			part_uv2.fill(Vector2(anchor.x, anchor.z))
			uv2.append_array(part_uv2)
		if part_indices.is_empty():
			for i in part_vertices.size():
				indices.append(start + i)
		else:
			for index in part_indices:
				indices.append(start + index)
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_TEX_UV] = uv
	if plant:
		surface[Mesh.ARRAY_TEX_UV2] = uv2
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## Фигурка человека лицом к −Z: комбинезон, рубашка, голова с глазами,
## ладони и ботинки. Головной убор и причёску добавляет вызывающий.
static func person(parent: Node3D, clothes: Color, shirt: Color, skin: Color, hand: Vector3) -> Node3D:
	const DARK := Color(0.22, 0.22, 0.26)
	var figure := Node3D.new()
	parent.add_child(figure)
	part(figure, capsule(0.24, 0.62), clothes, Vector3(0.0, 0.42, 0.0))
	part(figure, sphere(0.23), shirt, Vector3(0.0, 0.74, 0.0))
	part(figure, sphere(0.27), skin, Vector3(0.0, 1.12, 0.0))
	for side: float in [-1.0, 1.0]:
		part(figure, sphere(0.09), skin, hand * Vector3(side, 1.0, 1.0))
		part(figure, sphere(0.11), DARK, Vector3(0.13 * side, 0.09, -0.03))
		part(figure, sphere(0.035), DARK, Vector3(0.1 * side, 1.16, -0.24))
	return figure


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func sphere(radius: float, segments := 12) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = segments / 2
	return mesh


static func cylinder(radius: float, height: float, top_radius := -1.0, segments := 10,
		caps := true) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	# Без крышек: травинке и стеблю они не видны, а треугольники стоят.
	mesh.cap_top = caps
	mesh.cap_bottom = caps
	return mesh


static func prism(size: Vector3) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	return mesh


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	return mesh
