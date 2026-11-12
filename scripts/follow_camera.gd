class_name FollowCamera
extends Camera3D
## Камера сверху-сбоку: фиксированный наклон и поворот, плавно следует
## за целью с небольшим опережением, три ступени масштаба.

@export var target_path: NodePath
@export var pitch_degrees := 50.0
@export var yaw_degrees := 45.0
## Расстояния до цели для ступеней масштаба, от близкой к дальней.
@export var zoom_distances: Array[float] = [12.0, 17.0, 24.0]
@export var zoom_index := 1
@export var follow_speed := 5.0
@export var zoom_speed := 6.0
## Насколько камера смотрит вперёд по ходу движения, в метрах.
@export var look_ahead := 1.2

var _target: Node3D
var _focus := Vector3.ZERO
var _distance := 17.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	rotation_degrees = Vector3(-pitch_degrees, yaw_degrees, 0.0)
	zoom_index = clampi(zoom_index, 0, zoom_distances.size() - 1)
	_distance = zoom_distances[zoom_index]
	# На телефоне экран меньше — по умолчанию ближе.
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		zoom_index = 0
		_distance = zoom_distances[0]
	if _target:
		_focus = _target.global_position
	_apply()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		zoom_step(-1)
	elif event.is_action_pressed("zoom_out"):
		zoom_step(1)


func _process(delta: float) -> void:
	if _target:
		var wanted := _target.global_position
		var body := _target as CharacterBody3D
		if body:
			wanted += body.velocity.limit_length(1.0) * look_ahead
		_focus = _focus.lerp(wanted, 1.0 - exp(-follow_speed * delta))
	_distance = lerpf(_distance, zoom_distances[zoom_index], 1.0 - exp(-zoom_speed * delta))
	_apply()


## Меняет ступень масштаба: -1 — ближе, +1 — дальше.
func zoom_step(direction: int) -> void:
	zoom_index = clampi(zoom_index + direction, 0, zoom_distances.size() - 1)


func _apply() -> void:
	global_position = _focus + global_basis.z * _distance
