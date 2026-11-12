class_name Player
extends CharacterBody3D
## Персонаж с газонокосилкой.
##
## Косилка режет сама, пока движется. Назад не едет: разворот дугой.
## Источники ввода: клавиатура, геймпад и сенсорный джойстик (все через
## действия InputMap), а также удержание левой кнопки мыши (идти к курсору).

signal grass_collected(units: float)

## Скорость на обычной траве, м/с.
@export var speed := 2.5
## Скорость поворота, рад/с.
@export var turn_rate := 4.5
@export var acceleration := 9.0
## Ширина ножа в метрах.
@export var blade_width := 0.6
## Множитель скорости в высокой траве.
@export_range(0.1, 1.0) var tall_grass_speed := 0.6

## Расстояние от персонажа до центра ножа.
const BLADE_OFFSET := 0.95
const BLADE_LENGTH := 0.4
## Насколько игрок может выйти за край поляны (чтобы докосить края и развернуться).
const FIELD_MARGIN := 1.4
## Курсор ближе этого расстояния не двигает персонажа.
const MOUSE_DEADZONE := 1.3
const CHARACTER_SCALE := 1.15
## Положение правой ладони в координатах персонажа.
const HAND := Vector3(0.26, 0.82, -0.36)

var _field: MowField
var _pinch_zoom: PinchZoom
var _current_speed := 0.0
var _mouse_held := false
var _clippings: CPUParticles3D


func _ready() -> void:
	_field = get_tree().get_first_node_in_group("mow_field") as MowField
	_pinch_zoom = get_tree().get_first_node_in_group("pinch_zoom") as PinchZoom
	_build_visuals()


func _input(event: InputEvent) -> void:
	# Мышь, сэмулированную из касаний, пропускаем: на телефоне работает джойстик.
	if not event is InputEventMouseButton or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		# Клик по кнопкам интерфейса не должен двигать персонажа.
		var hovered := get_viewport().gui_get_hovered_control()
		_mouse_held = hovered == null or hovered is VirtualJoystick
	else:
		_mouse_held = false


func _physics_process(delta: float) -> void:
	var desired := _desired_direction()
	var strength := minf(desired.length(), 1.0)
	var forward := -global_basis.z
	var blade_position := global_position + forward * BLADE_OFFSET
	var target_speed := 0.0

	if strength > 0.05:
		var angle := forward.signed_angle_to(desired.normalized(), Vector3.UP)
		rotate_y(clampf(angle, -turn_rate * delta, turn_rate * delta))
		# Чем сильнее надо повернуть, тем медленнее едем — получается дуга, а не занос.
		var alignment := clampf(cos(angle), 0.0, 1.0)
		target_speed = speed * strength * lerpf(0.35, 1.0, alignment)
		if _field and _field.get_height_at(blade_position + forward * 0.25) > 0.8:
			target_speed *= tall_grass_speed

	_current_speed = move_toward(_current_speed, target_speed, acceleration * delta)
	forward = -global_basis.z
	velocity = forward * _current_speed
	move_and_slide()

	var units := 0.0
	if _field:
		global_position = _field.clamp_to_bounds(global_position, FIELD_MARGIN)
		blade_position = global_position + forward * BLADE_OFFSET
		_field.set_pusher_position(global_position + forward * BLADE_OFFSET * 0.6)
		if _current_speed > 0.1:
			units = _field.mow(blade_position, forward, blade_width, BLADE_LENGTH)
			if units > 0.0:
				grass_collected.emit(units)

	_clippings.emitting = units > 0.0


## Желаемое направление в мировых координатах, длина 0–1.
func _desired_direction() -> Vector3:
	# Пока игрок масштабирует камеру двумя пальцами, косилка стоит.
	if _pinch_zoom and _pinch_zoom.active:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO

	if input.length() > 0.01:
		# Движение относительно камеры: «вверх» — вглубь экрана.
		var right := camera.global_basis.x
		var ahead := -camera.global_basis.z
		right.y = 0.0
		ahead.y = 0.0
		return (right.normalized() * input.x - ahead.normalized() * input.y).limit_length(1.0)

	if _mouse_held:
		var mouse := get_viewport().get_mouse_position()
		var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(
				camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if hit != null:
			var to_cursor: Vector3 = hit - global_position
			to_cursor.y = 0.0
			if to_cursor.length() > MOUSE_DEADZONE:
				return to_cursor.normalized()

	return Vector3.ZERO


# Временный вид персонажа и косилки из примитивов (см. Placeholder).
func _build_visuals() -> void:
	const SKIN := Color(1.0, 0.82, 0.66)
	const OVERALLS := Color(0.27, 0.48, 0.80)
	const SHIRT := Color(0.98, 0.95, 0.86)
	const STRAW := Color(0.96, 0.82, 0.42)
	const RED := Color(0.90, 0.30, 0.26)
	const DARK := Color(0.22, 0.22, 0.26)
	const METAL := Color(0.72, 0.74, 0.78)
	const CANVAS := Color(0.55, 0.68, 0.42)

	var character := Node3D.new()
	character.name = "Character"
	character.scale = Vector3.ONE * CHARACTER_SCALE
	add_child(character)
	Placeholder.part(character, Placeholder.capsule(0.24, 0.62), OVERALLS, Vector3(0.0, 0.42, 0.0))
	Placeholder.part(character, Placeholder.sphere(0.23), SHIRT, Vector3(0.0, 0.74, 0.0))
	Placeholder.part(character, Placeholder.sphere(0.27), SKIN, Vector3(0.0, 1.12, 0.0))
	Placeholder.part(character, Placeholder.cylinder(0.42, 0.04), STRAW, Vector3(0.0, 1.33, 0.0))
	Placeholder.part(character, Placeholder.cylinder(0.24, 0.16, 0.19), STRAW, Vector3(0.0, 1.42, 0.0))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(character, Placeholder.sphere(0.09), SKIN, HAND * Vector3(side, 1.0, 1.0))
		Placeholder.part(character, Placeholder.sphere(0.11), DARK, Vector3(0.13 * side, 0.09, -0.03))

	# Косилка нарочно крупная и яркая, чтобы её было видно в высокой траве.
	var mower := Node3D.new()
	mower.name = "Mower"
	mower.position = Vector3(0.0, 0.0, -BLADE_OFFSET)
	add_child(mower)
	var deck_width := blade_width + 0.1
	Placeholder.part(mower, Placeholder.box(Vector3(deck_width, 0.26, 0.7)), RED, Vector3(0.0, 0.27, 0.0))
	Placeholder.part(mower, Placeholder.box(Vector3(deck_width + 0.06, 0.08, 0.08)), SHIRT, Vector3(0.0, 0.2, -0.37))
	Placeholder.part(mower, Placeholder.box(Vector3(0.4, 0.26, 0.36)), DARK, Vector3(0.0, 0.53, -0.06))
	Placeholder.part(mower, Placeholder.cylinder(0.09, 0.08), STRAW, Vector3(0.0, 0.7, -0.06))
	Placeholder.part(mower, Placeholder.box(Vector3(deck_width * 0.85, 0.4, 0.32)), CANVAS, Vector3(0.0, 0.4, 0.47))
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.24, 0.26]:
			Placeholder.part(mower, Placeholder.cylinder(0.15, 0.1), DARK,
					Vector3((deck_width * 0.5 + 0.04) * side, 0.15, z), Vector3(0.0, 0.0, 90.0))

	# Ручки тянутся от корпуса к ладоням персонажа.
	var grip := HAND * CHARACTER_SCALE + Vector3(0.0, 0.0, BLADE_OFFSET)
	var base := Vector3(grip.x, 0.4, 0.2)
	var handle_length := base.distance_to(grip)
	var handle_tilt := -rad_to_deg(atan2(grip.y - base.y, grip.z - base.z))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(mower, Placeholder.box(Vector3(0.05, 0.05, handle_length)), METAL,
				(base + grip) * 0.5 * Vector3(side, 1.0, 1.0), Vector3(handle_tilt, 0.0, 0.0))
	Placeholder.part(mower, Placeholder.box(Vector3(grip.x * 2.0 + 0.1, 0.05, 0.05)), METAL,
			Vector3(0.0, grip.y, grip.z))

	_clippings = CPUParticles3D.new()
	_clippings.name = "Clippings"
	_clippings.position = Vector3(0.0, 0.2, 0.15)
	_clippings.emitting = false
	_clippings.amount = 48
	_clippings.lifetime = 0.55
	_clippings.local_coords = false
	_clippings.mesh = Placeholder.box(Vector3(0.05, 0.012, 0.11))
	_clippings.material_override = Placeholder.material(Color(0.62, 0.86, 0.34))
	_clippings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clippings.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_clippings.emission_box_extents = Vector3(blade_width * 0.5, 0.03, 0.12)
	_clippings.direction = Vector3(0.0, 1.0, 0.25)
	_clippings.spread = 38.0
	_clippings.initial_velocity_min = 1.6
	_clippings.initial_velocity_max = 3.2
	_clippings.angular_velocity_min = -360.0
	_clippings.angular_velocity_max = 360.0
	_clippings.gravity = Vector3(0.0, -9.0, 0.0)
	_clippings.scale_amount_min = 0.7
	_clippings.scale_amount_max = 1.3
	mower.add_child(_clippings)
