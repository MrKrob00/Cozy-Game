class_name EventRainbow
extends Node3D
## Площадь: над починенным фонтаном встаёт радуга — полупрозрачная дуга из
## семи полос, обращённая к камере; проявляется, держится и тает. Пока
## фонтан сломан, событие ждёт починки (PlotEvents).

const RADIUS := 1.9
const WIDTH := 0.5
const SHOW := 2.5
const HOLD := 24.0
const HIDE := 3.5
const COLORS := [Color(0.95, 0.35, 0.35), Color(1.0, 0.62, 0.3), Color(1.0, 0.9, 0.4), Color(0.5, 0.85, 0.45),
		Color(0.42, 0.72, 0.98), Color(0.45, 0.48, 0.92), Color(0.7, 0.5, 0.9)]

var _arc: MeshInstance3D
var _material: StandardMaterial3D
var _time := 0.0


static func start(host: Node, fountain: Node3D) -> bool:
	if fountain == null:
		return false
	var rainbow := EventRainbow.new()
	rainbow.name = "Rainbow"
	host.add_child(rainbow)
	rainbow.global_position = fountain.global_position + Vector3.UP * 0.15
	return true


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.albedo_color = Color(1, 1, 1, 0)
	_arc = MeshInstance3D.new()
	_arc.mesh = _build_mesh()
	_arc.material_override = _material
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)
	Sfx.play("chime", -10.0, 1.3)
	Juice.sparkle(get_parent(), global_position + Vector3.UP * 1.5, Color(0.9, 0.95, 1.0), 20)


func _process(delta: float) -> void:
	_time += delta
	# Дуга смотрит на камеру (поворот только вокруг вертикали).
	var camera := get_viewport().get_camera_3d()
	if camera:
		var to := camera.global_position - global_position
		rotation.y = atan2(to.x, to.z)
	var alpha := 1.0
	if _time < SHOW:
		alpha = _time / SHOW
	elif _time > SHOW + HOLD:
		alpha = 1.0 - (_time - SHOW - HOLD) / HIDE
	_material.albedo_color.a = clampf(alpha, 0.0, 1.0) * 0.9
	if _time > SHOW + HOLD + HIDE:
		queue_free()


# Полукольцо в плоскости XY: семь цветных полос, к концам дуга тает.
func _build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var segments := 40
	var bands := COLORS.size()
	for b in bands + 1:
		var radius := RADIUS + WIDTH * 0.5 - WIDTH * b / bands
		for i in segments + 1:
			var angle := PI * i / segments
			vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
			var fade := sin(angle) ** 0.6
			var color: Color = COLORS[mini(b, bands - 1)]
			if b > 0 and b < bands:
				color = (COLORS[b - 1] as Color).lerp(COLORS[b], 0.5)
			colors.append(Color(color, fade))
	for b in bands:
		for i in segments:
			var a := b * (segments + 1) + i
			var c := a + segments + 1
			indices.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
