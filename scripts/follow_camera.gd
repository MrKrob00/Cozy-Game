class_name FollowCamera
extends Camera3D
## Камера сверху-сбоку: фиксированный наклон и поворот, плавно следует
## за целью с небольшим опережением, три ступени масштаба.

## Камера вернулась к игроку после показа точки (show_point).
signal reveal_finished

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
var _menu := false
const MENU_PULL_BACK := 9.0
## Скорость облёта на титульном экране, градусов в секунду.
const MENU_SPIN := 4.0
var _nudge_tween: Tween
var _flyover: Tween
# Показ точки (show_point): куда смотреть и насколько камера уже там, 0–1.
var _reveal_point := Vector3.ZERO
var _reveal_weight := 0.0
var _reveal: Tween
## Насколько камера отъезжает, пока показывает точку, метры.
const REVEAL_PULL_BACK := 3.0


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
	if _menu:
		_yaw_offset = fmod(_yaw_offset + MENU_SPIN * delta + 180.0, 360.0) - 180.0
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


## Титульный экран: камера отъезжает и медленно кружит над деревней.
func set_menu(on: bool) -> void:
	_menu = on
	if _flyover:
		_flyover.kill()
	if on:
		_distance_offset = MENU_PULL_BACK
		return
	_flyover = create_tween().set_parallel(true)
	_flyover.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flyover.tween_property(self, "_distance_offset", 0.0, 1.6)
	_flyover.tween_property(self, "_yaw_offset", 0.0, 1.6)


## Показывает точку вдали от игрока (калитку нового участка): камера едет
## к ней, задерживается и возвращается. on_arrive вызывается, когда камера
## на месте; в конце — сигнал reveal_finished.
func show_point(point: Vector3, on_arrive := Callable(), hold := 1.4) -> void:
	if _reveal:
		_reveal.kill()
	_reveal_point = point
	var travel := clampf(_focus.distance_to(point) / 16.0, 0.8, 1.6)
	_reveal = create_tween()
	_reveal.tween_property(self, "_reveal_weight", 1.0, travel) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if on_arrive.is_valid():
		_reveal.tween_callback(on_arrive)
	_reveal.tween_interval(hold)
	_reveal.tween_property(self, "_reveal_weight", 0.0, travel * 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_reveal.tween_callback(func() -> void: reveal_finished.emit())


## Идёт ли сейчас показ точки.
func is_revealing() -> bool:
	return _reveal != null and _reveal.is_running()


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
	var focus := _focus.lerp(_reveal_point, _reveal_weight)
	global_position = focus + global_basis.z * (_distance + _distance_offset + _nudge
			+ REVEAL_PULL_BACK * _reveal_weight)
