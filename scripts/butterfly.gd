class_name Butterfly
extends Node3D
## Бабочка, кружащая над клумбой.

@export var roam_radius := 0.9
@export var color := Color(1.0, 0.72, 0.3)

var _home := Vector3.ZERO
var _time := 0.0
var _phase := 0.0
var _wings: Array[Node3D] = []


func _ready() -> void:
	_home = position
	_phase = randf() * TAU
	_time = randf() * 10.0

	# Крылья — своя модель (две лопасти, кайма, пятнышки), окрашенная в цвет
	# бабочки; левое — отражённое правое.
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.vertex_color_use_as_albedo = true
	paint.albedo_color = color
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		add_child(pivot)
		var wing := MeshInstance3D.new()
		wing.mesh = Models.mesh("butterfly_wing")
		wing.material_override = paint
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing.scale = Vector3(side * 1.1, 1.0, 1.1)
		pivot.add_child(wing)
		_wings.append(pivot)
	var body := Models.place(self, "butterfly_body", Vector3.ZERO, 1.0, 0.0, false)
	body.set_meta("no_bake", true)


func _process(delta: float) -> void:
	_time += delta
	var before := position
	position = _home + Vector3(
			sin(_time * 0.9 + _phase) * roam_radius,
			0.75 + sin(_time * 1.7 + _phase * 2.0) * 0.2,
			cos(_time * 0.6 + _phase * 1.3) * roam_radius * 0.7)
	var heading := position - before
	if heading.length_squared() > 0.000001:
		rotation.y = atan2(-heading.x, -heading.z)
	var flap := absf(sin(_time * 16.0 + _phase))
	_wings[0].rotation.z = -(0.15 + flap * 1.0)
	_wings[1].rotation.z = 0.15 + flap * 1.0
