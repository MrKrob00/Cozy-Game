class_name Player
extends CharacterBody3D
## Персонаж с газонокосилкой.
##
## Косилка режет сама, пока движется и пока в мешке есть место.
## Назад не едет: разворот дугой. Скорость, ширина ножа и мешок берутся
## из апгрейдов (GameState).
## Источники ввода: клавиатура, геймпад и сенсорный джойстик (все через
## действия InputMap), а также удержание левой кнопки мыши (идти к курсору).

## Меняется объект, с которым сейчас можно взаимодействовать (или null).
signal interaction_target_changed(target: Interactable)

## Наибольшая скорость поворота, рад/с.
@export var turn_rate := 3.0
## Насколько охотно косилка доворачивает к нужному направлению (1/с).
## Малые отклонения исправляются мягко, поэтому она не дёргается.
@export var turn_response := 6.0
## Сглаживание направления ввода (1/с): гасит дрожание пальца на джойстике.
@export var input_smoothing := 10.0
@export var acceleration := 9.0
## Множитель скорости в высокой траве (с лучшим мотором замедление меньше).
@export_range(0.1, 1.0) var tall_grass_speed := 0.6
@export_range(0.1, 1.0) var tall_grass_speed_best_motor := 0.8
## Множитель скорости в бурьяне (когда нож его берёт).
@export_range(0.1, 1.0) var weed_speed := 0.45

## Расстояние от персонажа до центра ножа.
const BLADE_OFFSET := 0.95
## Покос шире ножа: до середины колёс (колёса стоят на blade_width / 2 + 0,09).
const CUT_EXTRA := 0.18
## Во сколько раз быстрее косилка катится вне участков (по улице).
const ROAD_SPEED_BOOST := 1.6
const BLADE_LENGTH := 0.4
## Курсор ближе этого расстояния не двигает персонажа.
const MOUSE_DEADZONE := 1.3
## Точка впереди персонажа, от которой меряется расстояние до объектов.
const REACH_OFFSET := 0.9
## Сколько секунд нужно пробыть рядом, чтобы простое действие выполнилось само.
const AUTO_INTERACT_DELAY := 0.4
const CHARACTER_SCALE := 1.15
## Через сколько метров покоса звучит очередной «вжух».
const SWISH_STEP := 0.55
## Положение правой ладони в координатах персонажа.
const HAND := Vector3(0.26, 0.82, -0.36)

var interaction_target: Interactable
## Пока выключено (титульный экран), игрок не слушается ввода.
var controls_enabled := true
## Текущие параметры косилки (из апгрейдов).
var speed := 2.5
var blade_width := 0.6

var _fields: Array[MowField] = []
var _walk_areas: Array[Node] = []
var _pinch_zoom: PinchZoom
var _current_speed := 0.0
var _mouse_held := false
var _clippings: CPUParticles3D
var _bag: MeshInstance3D
var _character: Node3D
var _mower_root: Node3D
var _mower: Node3D
var _engine_cap: MeshInstance3D
## Сколько метров проехано с последнего «вжуха» срезаемой травы.
var _swish_distance := 0.0
var _was_moving := false
var _idle_time := 0.0
var _exhaust: CPUParticles3D
var _bump_cooldown := 0.0
var _in_contact := false
# Состояние для анимации и звука.
var _walk_phase := 0.0
var _turn_speed := 0.0
var _cut_amount := 0.0
var _cutting := false
var _bag_ratio := 0.0
var _bag_shown := 0.0
var _time := 0.0
var _weed_hint_time := 0.0
var _smoothed_direction := Vector3.ZERO
var _road_boost := 0.0
var _terrain: Terrain
var _target_time := 0.0


func _enter_tree() -> void:
	add_to_group("shadow_dynamic")


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("mow_field"):
		_fields.append(node as MowField)
	_walk_areas = get_tree().get_nodes_in_group("walk_area")
	_terrain = Terrain.of(self)
	if _terrain:
		global_position.y = _terrain.height_at(Vector2(global_position.x, global_position.z))
	_pinch_zoom = get_tree().get_first_node_in_group("pinch_zoom") as PinchZoom
	_build_character()
	_apply_upgrades(false)
	GameState.bag_changed.connect(_on_bag_changed)
	GameState.upgrades_changed.connect(_apply_upgrades.bind(true))
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)
	_bag_shown = _bag_ratio


func _input(event: InputEvent) -> void:
	if not controls_enabled:
		return
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
	_smoothed_direction = _smoothed_direction.lerp(_desired_direction(),
			1.0 - exp(-input_smoothing * delta))
	var desired := _smoothed_direction
	var strength := minf(desired.length(), 1.0)
	var forward := -global_basis.z
	var target_speed := 0.0

	if strength > 0.05:
		var angle := forward.signed_angle_to(desired.normalized(), Vector3.UP)
		var turn := clampf(angle * minf(turn_response * delta, 1.0),
				-turn_rate * delta, turn_rate * delta)
		# Поворот вокруг косилки, а не вокруг персонажа: нож почти не уходит
		# в сторону, и ровную полосу вести легче.
		var pivot := get_blade_position()
		rotate_y(turn)
		global_position = pivot + (global_position - pivot).rotated(Vector3.UP, turn)
		_turn_speed = lerpf(_turn_speed, turn / delta, 0.2)
		# Чем сильнее надо повернуть, тем медленнее едем — получается дуга, а не занос.
		var alignment := clampf(cos(angle), 0.0, 1.0)
		target_speed = speed * strength * lerpf(0.35, 1.0, alignment)
		# За калиткой косить нечего: косилка катится быстрее.
		_road_boost = lerpf(_road_boost, 1.0 if _field_at(global_position) == null else 0.0,
				1.0 - exp(-3.0 * delta))
		target_speed *= 1.0 + (ROAD_SPEED_BOOST - 1.0) * _road_boost
		var ahead := _grass_height_at(get_blade_position() + forward * 0.25)
		if ahead > 0.9:
			# Бурьян: слабый нож в него упирается, хороший идёт медленно.
			if can_cut_weeds():
				target_speed *= weed_speed
			else:
				target_speed = 0.0
				_stuck_in_weeds()
		elif ahead > 0.7:
			target_speed *= tall_grass_speed_best_motor if GameState.is_upgrade_maxed("motor") \
					else tall_grass_speed
	else:
		_turn_speed = lerpf(_turn_speed, 0.0, 0.2)

	_current_speed = move_toward(_current_speed, target_speed, acceleration * delta)
	forward = -global_basis.z
	velocity = forward * _current_speed
	var before := global_position
	move_and_slide()
	var wanted := global_position
	global_position = _constrain(before, global_position)
	if _terrain:
		var ground := _terrain.height_at(Vector2(global_position.x, global_position.z))
		global_position.y = lerpf(global_position.y, ground, 1.0 - exp(-14.0 * delta))
	# Граница участка — это забор: упор в неё тоже считается ударом.
	var pushed_back := wanted - global_position
	_check_bump(target_speed, pushed_back.dot(-global_basis.z) > 0.004)

	var blade_position := get_blade_position()
	var pusher := global_position + forward * BLADE_OFFSET * 0.6
	for field in _fields:
		field.set_pusher_position(pusher)
	Placeholder.set_pusher(pusher)
	var units := 0.0
	if is_blade_spinning():
		var field := _field_at(blade_position)
		if field:
			units = field.mow(blade_position, forward, get_cut_width(), BLADE_LENGTH, can_cut_weeds())
			if units > 0.0:
				GameState.add_grass(units)

	_cutting = units > 0.0
	_clippings.emitting = _cutting
	_update_interaction(delta)


func _process(delta: float) -> void:
	_time += delta
	var pace := clampf(_current_speed / speed, 0.0, 1.0)
	var blend := 1.0 - exp(-10.0 * delta)

	# Персонаж шагает вперевалку и наклоняется в повороты.
	_walk_phase += _current_speed * delta * 7.0
	_character.position.y = absf(sin(_walk_phase)) * 0.06 * pace
	_character.rotation.z = sin(_walk_phase) * 0.07 * pace - _turn_speed * 0.035
	_character.rotation.x = -0.1 * pace

	# Тронулся или остановился — лёгкая пружинка.
	var moving := pace > 0.25
	if moving != _was_moving:
		_was_moving = moving
		Juice.squash(_character, 0.12 if moving else 0.08, 0.35, Vector3.ONE * CHARACTER_SCALE)
	# Постоял — дышит и оглядывается по сторонам.
	_idle_time = 0.0 if pace > 0.05 else _idle_time + delta
	var idle := clampf((_idle_time - 1.2) / 0.8, 0.0, 1.0)
	_character.position.y += sin(_time * 2.2) * 0.012 * idle
	_character.rotation.y = lerp_angle(_character.rotation.y,
			sin(_time * 0.6) * 0.45 * idle * signf(sin(_time * 0.21)), 1.0 - exp(-3.0 * delta))
	_exhaust.emitting = pace > 0.2
	_bump_cooldown -= delta

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

	# Мотора не слышно: только мягкий «вжух» травы, пока она режется.
	if _cutting:
		_swish_distance += _current_speed * delta
		if _swish_distance >= SWISH_STEP:
			_swish_distance = 0.0
			Sfx.play("swish", -9.0, 1.0, 0.15)


## Центр ножа в мировых координатах.
func get_blade_position() -> Vector3:
	return global_position - global_basis.z * BLADE_OFFSET


## Ширина полосы покоса, метры.
func get_cut_width() -> float:
	return blade_width + CUT_EXTRA


## Режет ли нож прямо сейчас: косилка едет и в мешке есть место.
func is_blade_spinning() -> bool:
	return _current_speed > 0.1 and not GameState.is_bag_full()


# Косилка с разгона упёрлась во что-то твёрдое (забор, дерево, зверёк):
# сплющивается, поднимается пыль, звучит мягкий «бум». Только в момент удара.
func _check_bump(target_speed: float, at_border: bool) -> void:
	var forward := -global_basis.z
	var contact := at_border
	var hit := get_blade_position() + forward * 0.4
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if forward.dot(-collision.get_normal()) > 0.55:
			contact = true
			hit = collision.get_position()
	if contact and not _in_contact and target_speed > 0.8 and _bump_cooldown <= 0.0:
		_bump_cooldown = 0.6
		Juice.squash(_mower_root, 0.2, 0.4)
		Juice.dust(get_parent(), Vector3(hit.x, 0.15, hit.z))
		Sfx.play("bonk", -5.0, 1.0, 0.1)
		Sfx.buzz(12)
	_in_contact = contact


## Берёт ли нож бурьян (нужен второй уровень ножа).
func can_cut_weeds() -> bool:
	return GameState.upgrade_level("blade") >= 1


# Косилка упёрлась в бурьян: трясётся и время от времени напоминает, что нужен нож получше.
func _stuck_in_weeds() -> void:
	_cut_amount = 1.0
	if _time < _weed_hint_time:
		return
	_weed_hint_time = _time + 9.0
	Sfx.play("deny", -4.0)
	GameState.toast("Бурьян не поддаётся. Нужен нож второго уровня — он есть в мастерской")


## Взаимодействует с ближайшим доступным объектом, если он есть.
func try_interact() -> void:
	if interaction_target and interaction_target.can_interact(self):
		interaction_target.interact(self)


func _field_at(world_position: Vector3) -> MowField:
	for field in _fields:
		if field.contains(world_position):
			return field
	return null


func _grass_height_at(world_position: Vector3) -> float:
	var field := _field_at(world_position)
	return field.get_height_at(world_position) if field else 0.0


# Удерживает игрока там, где можно ходить: участки, открытые калитки, улица.
# Если точка вне всех областей, она прижимается к краю той, где игрок стоял,
# поэтому вдоль заборов он скользит, а не застревает.
func _constrain(before: Vector3, after: Vector3) -> Vector3:
	var point := Vector2(after.x, after.z)
	var from := Vector2(before.x, before.z)
	var best := point
	var best_cost := INF
	var any := false
	for area in _walk_areas:
		for rect: Rect2 in area.get_walk_rects():
			any = true
			if rect.has_point(point):
				return after
			var clamped := point.clamp(rect.position, rect.end)
			var cost := clamped.distance_to(point)
			if not rect.grow(0.02).has_point(from):
				cost += 1000.0
			if cost < best_cost:
				best_cost = cost
				best = clamped
	if not any:
		return after
	return Vector3(best.x, after.y, best.y)


func _update_interaction(delta: float) -> void:
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
		_target_time = 0.0
		interaction_target_changed.emit(best)
	elif best and best.auto_interact:
		# Простые действия выполняются сами, если немного постоять рядом.
		_target_time += delta
		if _target_time >= AUTO_INTERACT_DELAY:
			_target_time = 0.0
			try_interact()


## Желаемое направление в мировых координатах, длина 0–1.
func _desired_direction() -> Vector3:
	if not controls_enabled:
		return Vector3.ZERO
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


# Применяет апгрейды: скорость, ширину ножа; косилка перестраивается под новый нож.
func _apply_upgrades(announce: bool) -> void:
	speed = GameState.upgrade_value("motor")
	blade_width = GameState.upgrade_value("blade")
	_build_mower()
	var mower_shape := get_node_or_null("MowerShape") as CollisionShape3D
	if mower_shape and mower_shape.shape is BoxShape3D:
		var box := mower_shape.shape as BoxShape3D
		box.size.x = blade_width + 0.1
	if announce:
		Juice.squash(_mower_root, 0.3)
		Juice.sparkle(self, _mower_root.global_position + Vector3.UP * 0.6)


# Временный вид персонажа из примитивов (см. Placeholder).
func _build_character() -> void:
	const STRAW := Color(0.96, 0.82, 0.42)
	_character = Placeholder.person(self, Color(0.27, 0.48, 0.80), Color(0.98, 0.95, 0.86),
			Color(1.0, 0.82, 0.66), HAND)
	_character.name = "Character"
	_character.scale = Vector3.ONE * CHARACTER_SCALE
	Placeholder.part(_character, Placeholder.cylinder(0.42, 0.04), STRAW, Vector3(0.0, 1.33, 0.0))
	Placeholder.part(_character, Placeholder.cylinder(0.24, 0.16, 0.19), STRAW, Vector3(0.0, 1.42, 0.0))
	Placeholder.bake_tree(_character)


# Временный вид косилки. Нарочно крупная и яркая, чтобы её было видно в высокой траве.
# Цвет корпуса и размер мотора меняются с апгрейдами.
func _build_mower() -> void:
	const CREAM := Color(0.98, 0.95, 0.86)
	const STRAW := Color(0.96, 0.82, 0.42)
	const DARK := Color(0.22, 0.22, 0.26)
	const METAL := Color(0.72, 0.74, 0.78)
	const CANVAS := Color(0.55, 0.68, 0.42)
	const BODY_COLORS := [Color(0.90, 0.30, 0.26), Color(0.95, 0.55, 0.20), Color(0.30, 0.62, 0.85)]

	if _mower_root:
		_mower_root.free()
	_mower_root = Node3D.new()
	_mower_root.name = "Mower"
	_mower_root.position = Vector3(0.0, 0.0, -BLADE_OFFSET)
	add_child(_mower_root)
	# Отдельный узел, чтобы тряска мотора не сдвигала саму косилку.
	_mower = Node3D.new()
	_mower_root.add_child(_mower)

	var body_color: Color = BODY_COLORS[mini(GameState.upgrade_level("blade"), BODY_COLORS.size() - 1)]
	var engine := 1.0 + 0.18 * GameState.upgrade_level("motor")
	var deck_width := blade_width + 0.1
	Placeholder.part(_mower, Placeholder.box(Vector3(deck_width, 0.26, 0.7)), body_color, Vector3(0.0, 0.27, 0.0))
	Placeholder.part(_mower, Placeholder.box(Vector3(deck_width + 0.06, 0.08, 0.08)), CREAM, Vector3(0.0, 0.2, -0.37))
	Placeholder.part(_mower, Placeholder.box(Vector3(0.4 * engine, 0.26, 0.36 * engine)), DARK, Vector3(0.0, 0.53, -0.06))
	_engine_cap = Placeholder.part(_mower, Placeholder.cylinder(0.09 * engine, 0.08), STRAW, Vector3(0.0, 0.7, -0.06))
	_engine_cap.set_meta("no_bake", true)
	_bag = Placeholder.part(_mower, Placeholder.box(Vector3(deck_width * 0.85, 0.4, 0.32)), CANVAS)
	_bag.set_meta("no_bake", true)
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.24, 0.26]:
			Placeholder.part(_mower, Placeholder.cylinder(0.15, 0.1), DARK,
					Vector3((deck_width * 0.5 + 0.04) * side, 0.15, z), Vector3(0.0, 0.0, 90.0))

	# Ручки тянутся от корпуса к ладоням персонажа.
	var grip := HAND * CHARACTER_SCALE + Vector3(0.0, 0.0, BLADE_OFFSET)
	var base := Vector3(grip.x, 0.4, 0.2)
	var handle_length := base.distance_to(grip)
	var handle_tilt := -rad_to_deg(atan2(grip.y - base.y, grip.z - base.z))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(_mower, Placeholder.box(Vector3(0.05, 0.05, handle_length)), METAL,
				(base + grip) * 0.5 * Vector3(side, 1.0, 1.0), Vector3(handle_tilt, 0.0, 0.0))
	Placeholder.part(_mower, Placeholder.box(Vector3(grip.x * 2.0 + 0.1, 0.05, 0.05)), METAL,
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
	_clippings.emission_box_extents = Vector3(get_cut_width() * 0.5, 0.03, 0.12)
	_clippings.direction = Vector3(0.0, 1.0, 0.25)
	_clippings.spread = 38.0
	_clippings.initial_velocity_min = 1.6
	_clippings.initial_velocity_max = 3.2
	_clippings.angular_velocity_min = -360.0
	_clippings.angular_velocity_max = 360.0
	_clippings.gravity = Vector3(0.0, -9.0, 0.0)
	_clippings.scale_amount_min = 0.7
	_clippings.scale_amount_max = 1.3
	_mower.add_child(_clippings)

	# Маленькие облачка из мотора: косилку не слышно, зато видно, что она работает.
	_exhaust = CPUParticles3D.new()
	_exhaust.name = "Exhaust"
	_exhaust.position = Vector3(0.0, 0.78, -0.06)
	_exhaust.emitting = false
	_exhaust.amount = 6
	_exhaust.lifetime = 0.9
	_exhaust.local_coords = false
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.06
	puff_mesh.height = 0.12
	puff_mesh.radial_segments = 6
	puff_mesh.rings = 3
	_exhaust.mesh = puff_mesh
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.vertex_color_use_as_albedo = true
	_exhaust.material_override = puff
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.7), Color(1.0, 1.0, 1.0, 0.0)])
	_exhaust.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.8))
	_exhaust.scale_amount_curve = grow
	_exhaust.direction = Vector3(0.0, 1.0, 0.3)
	_exhaust.spread = 20.0
	_exhaust.initial_velocity_min = 0.4
	_exhaust.initial_velocity_max = 0.7
	_exhaust.gravity = Vector3(0.0, 0.3, 0.0)
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mower.add_child(_exhaust)
	Placeholder.bake_tree(_mower_root)
