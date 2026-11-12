class_name Player
extends CharacterBody3D
## Персонаж с газонокосилкой.
##
## Косилка режет сама, пока движется и пока в мешке есть место.
## Назад не едет: разворот дугой.
## Источники ввода: клавиатура, геймпад и сенсорный джойстик (все через
## действия InputMap), а также удержание левой кнопки мыши (идти к курсору).

## Меняется объект, с которым сейчас можно взаимодействовать (или null).
signal interaction_target_changed(target: Interactable)

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
## Насколько игрок может выйти за край поля (чтобы докосить края и развернуться).
const FIELD_MARGIN := 1.4
## Курсор ближе этого расстояния не двигает персонажа.
const MOUSE_DEADZONE := 1.3
## Точка впереди персонажа, от которой меряется расстояние до объектов.
const REACH_OFFSET := 0.9
const CHARACTER_SCALE := 1.15
## Положение правой ладони в координатах персонажа.
const HAND := Vector3(0.26, 0.82, -0.36)

var interaction_target: Interactable

var _field: MowField
var _pinch_zoom: PinchZoom
var _current_speed := 0.0
var _mouse_held := false
var _clippings: CPUParticles3D
var _bag: MeshInstance3D
var _character: Node3D
var _mower: Node3D
var _engine_cap: MeshInstance3D
var _engine_sound: AudioStreamPlayer
var _cut_sound: AudioStreamPlayer
# Состояние для анимации и звука.
var _walk_phase := 0.0
var _turn_speed := 0.0
var _cut_amount := 0.0
var _cutting := false
var _bag_ratio := 0.0
var _bag_shown := 0.0
var _time := 0.0


func _ready() -> void:
	_field = get_tree().get_first_node_in_group("mow_field") as MowField
	_pinch_zoom = get_tree().get_first_node_in_group("pinch_zoom") as PinchZoom
	_build_visuals()
	_engine_sound = Sfx.create_loop("mower_loop", self)
	_cut_sound = Sfx.create_loop("cut_loop", self)
	GameState.bag_changed.connect(_on_bag_changed)
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)
	_bag_shown = _bag_ratio


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		try_interact()
		return
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
		var turn := clampf(angle, -turn_rate * delta, turn_rate * delta)
		rotate_y(turn)
		_turn_speed = lerpf(_turn_speed, turn / delta, 0.2)
		# Чем сильнее надо повернуть, тем медленнее едем — получается дуга, а не занос.
		var alignment := clampf(cos(angle), 0.0, 1.0)
		target_speed = speed * strength * lerpf(0.35, 1.0, alignment)
		if _field and _field.get_height_at(blade_position + forward * 0.25) > 0.8:
			target_speed *= tall_grass_speed
	else:
		_turn_speed = lerpf(_turn_speed, 0.0, 0.2)

	_current_speed = move_toward(_current_speed, target_speed, acceleration * delta)
	forward = -global_basis.z
	velocity = forward * _current_speed
	move_and_slide()

	var units := 0.0
	if _field:
		global_position = _field.clamp_to_bounds(global_position, FIELD_MARGIN)
		blade_position = global_position + forward * BLADE_OFFSET
		_field.set_pusher_position(global_position + forward * BLADE_OFFSET * 0.6)
		# Полный мешок останавливает нож: ехать можно, косить — нет.
		if _current_speed > 0.1 and not GameState.is_bag_full():
			units = _field.mow(blade_position, forward, blade_width, BLADE_LENGTH)
			if units > 0.0:
				GameState.add_grass(units)

	_cutting = units > 0.0
	_clippings.emitting = _cutting
	_update_interaction()


func _process(delta: float) -> void:
	_time += delta
	var pace := clampf(_current_speed / speed, 0.0, 1.0)
	var blend := 1.0 - exp(-10.0 * delta)

	# Персонаж шагает вперевалку и наклоняется в повороты.
	_walk_phase += _current_speed * delta * 7.0
	_character.position.y = absf(sin(_walk_phase)) * 0.06 * pace
	_character.rotation.z = sin(_walk_phase) * 0.07 * pace - _turn_speed * 0.035
	_character.rotation.x = -0.1 * pace

	# Косилка мелко дрожит от мотора, сильнее на ходу и в густой траве.
	_cut_amount = lerpf(_cut_amount, 1.0 if _cutting else 0.0, blend)
	var shake := 0.004 + 0.006 * pace + 0.008 * _cut_amount
	_mower.position.y = sin(_time * 47.0) * shake
	_mower.rotation.z = sin(_time * 39.0) * shake * 1.5 - _turn_speed * 0.02
	_engine_cap.position.y = 0.7 + absf(sin(_time * 23.0)) * (0.01 + 0.02 * pace)

	# Мешок плавно раздувается; при опустошении сдувается, полный — подрагивает.
	_bag_shown = lerpf(_bag_shown, _bag_ratio, blend)
	var height := lerpf(0.55, 1.25, _bag_shown)
	var depth := lerpf(0.7, 1.3, _bag_shown)
	var wobble := sin(_time * 14.0) * 0.04 if _bag_ratio >= 0.999 else 0.0
	_bag.scale = Vector3(1.0 + wobble, height - wobble, depth)
	_bag.position = Vector3(0.0, 0.2 + 0.2 * height, 0.31 + 0.16 * depth)

	# Мотор урчит тише на месте и бодрее на ходу; шелест слышен, пока трава режется.
	_engine_sound.volume_db = linear_to_db(lerpf(0.07, 0.22, pace))
	_engine_sound.pitch_scale = lerpf(0.82, 1.12, pace) - 0.08 * _cut_amount
	_cut_sound.volume_db = linear_to_db(maxf(_cut_amount * 0.3, 0.0001))


## Взаимодействует с ближайшим доступным объектом, если он есть.
func try_interact() -> void:
	if interaction_target and interaction_target.can_interact(self):
		interaction_target.interact(self)


func _update_interaction() -> void:
	var reach := global_position - global_basis.z * REACH_OFFSET
	var best: Interactable = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		var item := node as Interactable
		if item == null or not item.can_interact(self):
			continue
		var offset := item.global_position - reach
		offset.y = 0.0
		var distance := offset.length()
		if distance <= item.interact_radius and distance < best_distance:
			best = item
			best_distance = distance
	if best != interaction_target:
		interaction_target = best
		interaction_target_changed.emit(best)


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


func _on_bag_changed(fill: float, capacity: float) -> void:
	_bag_ratio = clampf(fill / maxf(capacity, 1.0), 0.0, 1.0)


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
	_character = character
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
	var mower_root := Node3D.new()
	mower_root.name = "Mower"
	mower_root.position = Vector3(0.0, 0.0, -BLADE_OFFSET)
	add_child(mower_root)
	# Отдельный узел, чтобы тряска мотора не сдвигала саму косилку.
	var mower := Node3D.new()
	_mower = mower
	mower_root.add_child(mower)
	var deck_width := blade_width + 0.1
	Placeholder.part(mower, Placeholder.box(Vector3(deck_width, 0.26, 0.7)), RED, Vector3(0.0, 0.27, 0.0))
	Placeholder.part(mower, Placeholder.box(Vector3(deck_width + 0.06, 0.08, 0.08)), SHIRT, Vector3(0.0, 0.2, -0.37))
	Placeholder.part(mower, Placeholder.box(Vector3(0.4, 0.26, 0.36)), DARK, Vector3(0.0, 0.53, -0.06))
	_engine_cap = Placeholder.part(mower, Placeholder.cylinder(0.09, 0.08), STRAW, Vector3(0.0, 0.7, -0.06))
	_bag = Placeholder.part(mower, Placeholder.box(Vector3(deck_width * 0.85, 0.4, 0.32)), CANVAS)
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
