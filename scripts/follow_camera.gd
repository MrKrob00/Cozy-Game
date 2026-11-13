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
@export var follow_speed := 4.0
@export var zoom_speed := 6.0
## Насколько камера смотрит вперёд по ходу движения, в метрах.
@export var look_ahead := 0.7
## Как быстро опережение подстраивается под новое направление (1/с).
## Малое значение не даёт камере метаться, когда косилка поворачивает.
@export var look_ahead_speed := 1.2

var _target: Node3D
var _focus := Vector3.ZERO
var _ahead := Vector3.ZERO
var _distance := 17.0
# Добавки на время облёта (см. play_flyover).
var _yaw_offset := 0.0
var _distance_offset := 0.0
# Короткий наезд камеры (nudge).
var _nudge := 0.0
var _nudge_tween: Tween
var _flyover: Tween


func _ready() -> void:
	cull_mask &= ~Shadows.LAYER
	_target = get_node_or_null(target_path) as Node3D
	zoom_index = clampi(zoom_index, 0, zoom_distances.size() - 1)
	# На телефоне экран меньше — по умолчанию ближе.
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		zoom_index = 0
	_distance = zoom_distances[zoom_index]
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
			_ahead = _ahead.lerp(body.velocity.limit_length(1.0) * look_ahead,
					1.0 - exp(-look_ahead_speed * delta))
			wanted += _ahead
		_focus = _focus.lerp(wanted, 1.0 - exp(-follow_speed * delta))
	_distance = lerpf(_distance, zoom_distances[zoom_index], 1.0 - exp(-zoom_speed * delta))
	_apply()


## Меняет ступень масштаба: -1 — ближе, +1 — дальше.
func zoom_step(direction: int) -> void:
	zoom_index = clampi(zoom_index + direction, 0, zoom_distances.size() - 1)


## Короткий облёт: камера отъезжает и поворачивается вокруг цели, затем возвращается.
func play_flyover(duration := 6.0, swing_degrees := 70.0, pull_back := 7.0) -> void:
	if _flyover:
		_flyover.kill()
	_flyover = create_tween()
	_flyover.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flyover.tween_property(self, "_yaw_offset", swing_degrees, duration * 0.5)
	_flyover.parallel().tween_property(self, "_distance_offset", pull_back, duration * 0.5)
	_flyover.tween_property(self, "_yaw_offset", 0.0, duration * 0.5)
	_flyover.parallel().tween_property(self, "_distance_offset", 0.0, duration * 0.5)


## Короткий наезд: камера на миг приближается на amount метров и возвращается.
func nudge(amount := 1.2, duration := 0.8) -> void:
	if _nudge_tween:
		_nudge_tween.kill()
	_nudge_tween = create_tween()
	_nudge_tween.tween_property(self, "_nudge", -amount, duration * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(self, "_nudge", 0.0, duration * 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply() -> void:
	rotation_degrees = Vector3(-pitch_degrees, yaw_degrees + _yaw_offset, 0.0)
	global_position = _focus + global_basis.z * (_distance + _distance_offset + _nudge)
