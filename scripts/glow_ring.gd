class_name GlowRing
extends Node3D
## Мягкий световой круг на земле: «сюда». Тонкое кольцо и расходящиеся от
## него волны. Им отмечены полный мешок → компостный ящик и только что
## открытая калитка (вместо вращающейся стрелки над ними).

const COLOR := Color(1.0, 0.86, 0.36)
## Волна расходится за столько секунд; новая — сразу следом.
const RIPPLE_TIME := 1.6

var radius := 1.0

var _ring: MeshInstance3D
var _ripple: MeshInstance3D
var _ripple_material: StandardMaterial3D
var _time := 0.0

static var _mesh: ArrayMesh
static var _disc: ArrayMesh


static func create(ring_radius: float) -> GlowRing:
	var ring := GlowRing.new()
	ring.radius = ring_radius
	return ring


func _ready() -> void:
	# Мягкая заливка внутри — круг читается пятном света, не ниткой.
	_make(Color(COLOR, 0.14), _disc_mesh())
	_ring = _make(Color(COLOR, 0.6))
	_ripple = _make(Color(COLOR, 0.5))
	_ripple_material = _ripple.material_override
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	var t := fmod(_time, RIPPLE_TIME) / RIPPLE_TIME
	_ripple.scale = Vector3.ONE * radius * lerpf(0.75, 1.5, t)
	_ripple_material.albedo_color.a = 0.5 * (1.0 - t)
	_ring.scale = Vector3.ONE * radius * (1.0 + sin(_time * 3.0) * 0.04)


## Плавно гаснет и исчезает.
func vanish() -> void:
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _make(color: Color, mesh: Mesh = null) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh if mesh else _ring_mesh()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position.y = 0.04
	instance.scale = Vector3.ONE * radius
	add_child(instance)
	return instance


# Круг радиусом 0,9 (внутри кольца), лежит на земле.
static func _disc_mesh() -> ArrayMesh:
	if _disc:
		return _disc
	var vertices := PackedVector3Array([Vector3.ZERO])
	var indices := PackedInt32Array()
	var segments := 32
	for i in segments:
		var angle := TAU * i / segments
		vertices.append(Vector3(cos(angle), 0.0, sin(angle)) * 0.9)
		indices.append_array([0, 1 + (i + 1) % segments, 1 + i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	_disc = ArrayMesh.new()
	_disc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _disc


# Плоское кольцо радиусом 1 (ширина 0,2), лежит на земле.
static func _ring_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var vertices := PackedVector3Array()
	var segments := 48
	for i in segments:
		for edge in 2:
			var angle := TAU * (i + edge) / segments
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(direction * 0.9)
			vertices.append(direction * 1.1)
	var indices := PackedInt32Array()
	for i in segments:
		var a := i * 4
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh
