class_name FollowCamera
extends Camera3D
## Камера сверху-сбоку: фиксированный наклон и поворот, плавно следует
## за целью с небольшим опережением, три ступени масштаба.
##
## Второй режим (настройка «Камера: сзади», GameState.camera_mode) — за
## спиной героя, ниже и ближе: камера поворачивается следом за героем, пока
## он едет от неё; развернувшись к камере, герой едет на неё, и она не
## крутится (иначе управление «на себя» закручивало бы всё по кругу).
## Показ калиток и титульный экран — всегда сверху; переходы плавные.

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
## Насколько камера отъезжает, когда цель быстро едет по дороге, метры.
const TRAVEL_PULL_BACK := 2.2
var _travel := 0.0
## Насколько камера отъезжает, пока показывает точку, метры.
const REVEAL_PULL_BACK := 3.0
## Камера сзади: наклон, расстояния по ступеням масштаба, куда смотрит
## (над землёй у героя и впереди него), как быстро догоняет поворот героя.
const CHASE_PITCH := 28.0
const CHASE_DISTANCES: Array[float] = [6.0, 7.6, 9.8]
const CHASE_HEIGHT := 0.6
const CHASE_AHEAD := 1.2
const CHASE_TURN := 2.2
## Камера чуть сбоку (радианы вокруг героя): видно и героя, и косилку перед ним.
const CHASE_SIDE := 0.7
## Если сзади стена или холм, камера поднимается (до такого наклона), пока
## путь до героя не станет свободным; расстояние не меняется.
const CHASE_PITCH_HIGH := 72.0
## Дальше этого угла (герой повернулся к камере) камера за ним не поворачивает.
const CHASE_FOLLOW_ANGLE := 1.9

## Насколько камера сейчас «сзади», 0–1, и её поворот (как у героя).
var _chase := 0.0
var _chase_yaw := 0.0
var _chase_distance := 6.4
## Насколько камера сейчас поднята из-за стены, 0–1.
var _chase_lift := 0.0


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
		_chase_yaw = _target.global_rotation.y
	_chase = 1.0 if GameState.camera_mode == 1 else 0.0
	_chase_distance = CHASE_DISTANCES[zoom_index]
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
	# В дороге камера плавно отъезжает, на участке возвращается.
	var travelling: float = _target.get("travel") if _target and _target.get("travel") != null else 0.0
	_travel = lerpf(_travel, travelling, 1.0 - exp(-1.5 * delta))
	_update_chase(delta)
	_apply()


# Режим «сзади»: насколько он включён и куда смотрит камера.
func _update_chase(delta: float) -> void:
	var wanted := 1.0 if GameState.camera_mode == 1 and not _menu else 0.0
	if _chase <= 0.0 and wanted > 0.0 and _target:
		_chase_yaw = _target.global_rotation.y
	_chase = move_toward(_chase, wanted, delta * 1.2)
	if _chase <= 0.0 or _target == null:
		return
	var body := _target as CharacterBody3D
	var pace := clampf(body.velocity.length() / 2.0, 0.2, 1.0) if body else 1.0
	_chase_distance = lerpf(_chase_distance, CHASE_DISTANCES[zoom_index], 1.0 - exp(-zoom_speed * delta))
	var forward := Vector3(-sin(_chase_yaw), 0.0, -cos(_chase_yaw))
	var lift := _clear_lift(_focus + Vector3.UP * CHASE_HEIGHT + forward * CHASE_AHEAD, _chase_distance)
	# Вверх — быстро (стена не должна закрыть героя), обратно — плавно.
	var rate := 8.0 if lift > _chase_lift else 1.5
	_chase_lift = lerpf(_chase_lift, lift, 1.0 - exp(-rate * delta))
	var turn := angle_difference(_chase_yaw, _target.global_rotation.y)
	if absf(turn) < CHASE_FOLLOW_ANGLE:
		_chase_yaw += turn * (1.0 - exp(-CHASE_TURN * pace * delta))


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
	var pitch := pitch_degrees
	var yaw := deg_to_rad(yaw_degrees + _yaw_offset)
	var focus := _focus.lerp(_reveal_point, _reveal_weight)
	var distance := _distance + _distance_offset + _nudge + REVEAL_PULL_BACK * _reveal_weight \
			+ TRAVEL_PULL_BACK * _travel
	# Сзади: на время показа калитки камера уходит наверх.
	var chase := _chase * (1.0 - _reveal_weight)
	if chase > 0.0:
		var forward := Vector3(-sin(_chase_yaw), 0.0, -cos(_chase_yaw))
		var chase_focus := _focus + Vector3.UP * CHASE_HEIGHT + forward * CHASE_AHEAD
		var weight := smoothstep(0.0, 1.0, chase)
		pitch = lerpf(pitch, lerpf(CHASE_PITCH, CHASE_PITCH_HIGH, _chase_lift), weight)
		yaw = lerp_angle(yaw, _chase_yaw + CHASE_SIDE, weight)
		focus = focus.lerp(chase_focus, weight)
		distance = lerpf(distance, _chase_distance + _nudge * 0.5, weight)
	rotation = Vector3(deg_to_rad(-pitch), yaw, 0.0)
	global_position = focus + global_basis.z * distance


# Камера сзади не залезает в дома и холмы: наименьший подъём (0–1), при
# котором путь от героя до камеры свободен.
func _clear_lift(focus: Vector3, distance: float) -> float:
	if not is_inside_tree():
		return 0.0
	var space := get_world_3d().direct_space_state
	for step in 5:
		var lift := step / 4.0
		var pitch := deg_to_rad(lerpf(CHASE_PITCH, CHASE_PITCH_HIGH, lift))
		var back := Basis.from_euler(Vector3(-pitch, _chase_yaw + CHASE_SIDE, 0.0)).z
		var query := PhysicsRayQueryParameters3D.create(focus, focus + back * distance)
		if _target is CollisionObject3D:
			query.exclude = [(_target as CollisionObject3D).get_rid()]
		if space.intersect_ray(query).is_empty():
			return lift
	return 1.0
