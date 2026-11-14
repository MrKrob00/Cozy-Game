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
## Множитель скорости в бурьяне. Слабый нож его не режет, но косилка
## всё равно продирается сквозь заросли, только медленно.
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
## Отклонение джойстика, с которого косилка едет в полную силу: вести
## скорость пальцем неудобно, поэтому полный ход включается рано.
const FULL_SPEED_INPUT := 0.55
## Разворот: если нужное направление почти за спиной (дальше этого угла),
## косилка не меняет сторону, в которую уже поворачивает.
const TURN_COMMIT_ANGLE := 2.3
## Точка впереди персонажа, от которой меряется расстояние до объектов.
const REACH_OFFSET := 0.9
## Сколько секунд нужно пробыть рядом, чтобы простое действие выполнилось само.
const AUTO_INTERACT_DELAY := 0.4
## Рост героя, метры (модель Kenney Mini Characters подгоняется под него).
const HERO_HEIGHT := 1.5
## Где стоит герой относительно точки игрока: чуть позади, чтобы ладони
## ложились на ручку косилки, а мешок помещался между ним и косилкой.
const HERO_OFFSET := Vector3(0.0, 0.0, 0.12)
## Шляпа: во сколько раз тулья уже головы и насколько она надета, метры.
const HAT_FIT := 0.86
const HAT_SINK := 0.1
## Радиус колеса косилки (tools/make_models.py), метры.
const WHEEL_RADIUS := 0.15

var interaction_target: Interactable
## Сенсорная схема «вести пальцем» (ставит интерфейс; null — джойстик).
var touch_pad: TouchPad
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
var _hero: CharacterModel
var _wheels: Array[MeshInstance3D] = []
var _wheel_turn := 0.0
var _engine_top := 0.0
var _mower_root: Node3D
var _mower: Node3D
var _engine_cap: MeshInstance3D
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
## Сторона начатого разворота: −1, 0 или 1.
var _turn_side := 0.0


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
		# Цель почти за спиной: знак угла там скачет от дрожи пальца, и
		# косилка рыскала бы влево-вправо. Доворачиваем в начатую сторону.
		if absf(angle) < 0.15:
			_turn_side = 0.0
		elif _turn_side == 0.0 or absf(angle) < TURN_COMMIT_ANGLE:
			_turn_side = signf(angle)
		elif signf(angle) != _turn_side:
			angle = _turn_side * (TAU - absf(angle))
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
			# Бурьян: ехать можно, но медленно; срезает его только нож получше.
			target_speed *= weed_speed
			if not can_cut_weeds():
				_weeds_hint()
		elif ahead > 0.7:
			target_speed *= tall_grass_speed_best_motor if GameState.is_upgrade_maxed("motor") \
					else tall_grass_speed
	else:
		_turn_speed = lerpf(_turn_speed, 0.0, 0.2)
		_turn_side = 0.0

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

	# Герой катит косилку: шаги — анимация модели в темпе хода, в повороты
	# он слегка наклоняется.
	if pace > 0.06:
		_hero.play("push-walk", clampf(_current_speed / 1.9, 0.5, 2.2))
	else:
		_hero.play("push-idle")
	_character.rotation.z = lerpf(_character.rotation.z, -_turn_speed * 0.03, blend)
	_character.rotation.x = lerpf(_character.rotation.x, -0.06 * pace, blend)

	# Тронулся или остановился — лёгкая пружинка.
	var moving := pace > 0.25
	if moving != _was_moving:
		_was_moving = moving
		Juice.squash(_character, 0.1 if moving else 0.06, 0.35)
	_idle_time = 0.0 if pace > 0.05 else _idle_time + delta
	_exhaust.emitting = pace > 0.2
	_bump_cooldown -= delta

	# Косилка мелко дрожит от мотора, сильнее на ходу и в густой траве.
	_cut_amount = lerpf(_cut_amount, 1.0 if _cutting else 0.0, blend)
	var shake := 0.004 + 0.006 * pace + 0.008 * _cut_amount
	_mower.position.y = sin(_time * 47.0) * shake
	_mower.rotation.z = sin(_time * 39.0) * shake * 1.5 - _turn_speed * 0.02
	_engine_cap.position.y = _engine_top + absf(sin(_time * 23.0)) * (0.008 + 0.02 * pace)
	# Колёса катятся по пройденному пути.
	_wheel_turn -= _current_speed * delta / WHEEL_RADIUS
	for wheel in _wheels:
		wheel.rotation.x = _wheel_turn

	# Мешок плавно раздувается; при опустошении сдувается, полный — подрагивает.
	_bag_shown = lerpf(_bag_shown, _bag_ratio, blend)
	var height := lerpf(0.6, 1.1, _bag_shown)
	var depth := lerpf(0.6, 0.92, _bag_shown)
	var wobble := sin(_time * 14.0) * 0.04 if _bag_ratio >= 0.999 else 0.0
	_bag.scale = Vector3(0.87 + wobble, height - wobble, depth)

	# Косилка беззвучна: ни мотора, ни звука среза. О покосе говорят летящая
	# трава и полосы на газоне (повторяющийся звук игроку мешал).


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


# Косилка продирается сквозь бурьян, не срезая его: трясётся и время от
# времени напоминает, что нужен нож получше.
func _weeds_hint() -> void:
	_cut_amount = 1.0
	if _time < _weed_hint_time:
		return
	_weed_hint_time = _time + 12.0
	Sfx.play("deny", -8.0)
	GameState.toast("Бурьян этот нож не берёт. Нужен нож второго уровня — он есть в мастерской")


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
		var direction := right.normalized() * input.x - ahead.normalized() * input.y
		return direction.normalized() * minf(direction.length() / FULL_SPEED_INPUT, 1.0)

	# Мышь на компьютере или палец в схеме «вести пальцем»: едем к этой точке.
	var finger := touch_pad != null and touch_pad.held
	if _mouse_held or finger:
		var mouse := touch_pad.finger if finger else get_viewport().get_mouse_position()
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


# Герой — модель Kenney Mini Characters в соломенной шляпе. Анимация «катит
# косилку» складывается из шагов и позы «держит двумя руками».
func _build_character() -> void:
	_character = Node3D.new()
	_character.name = "Character"
	_character.position = HERO_OFFSET
	add_child(_character)
	_hero = CharacterModel.create("res://assets/characters/hero.glb", HERO_HEIGHT)
	# Модель смотрит на +Z, игрок — на −Z.
	_hero.rotation.y = PI
	_character.add_child(_hero)
	var arms: Array[String] = ["arm-left", "arm-right"]
	_hero.combine("push-walk", "walk", "holding-both", arms)
	_hero.combine("push-idle", "idle", "holding-both", arms)
	_hero.play("push-idle", 1.0, 0.0)
	# Соломенная шляпа по размеру головы; держится на кости головы.
	var head := _hero.part_box("head-mesh")
	var hat_scale := head.size.x * 0.5 / 0.2 * HAT_FIT
	var hat := Models.place(_hero.attach("head"), "straw_hat",
			Vector3(0.0, head.end.y - _hero.bone_height("head") - HAT_SINK, 0.0), hat_scale, 0.0, false)
	hat.set_meta("no_bake", true)


# Косилка из своих моделей (tools/make_models.py): корпус по уровню ножа,
# мотор растёт с улучшением, колёса крутятся, мешок раздувается.
func _build_mower() -> void:
	if _mower_root:
		_mower_root.free()
	_wheels.clear()
	_mower_root = Node3D.new()
	_mower_root.name = "Mower"
	_mower_root.position = Vector3(0.0, 0.0, -BLADE_OFFSET)
	add_child(_mower_root)
	# Отдельный узел, чтобы тряска мотора не сдвигала саму косилку.
	_mower = Node3D.new()
	_mower_root.add_child(_mower)

	var level := mini(GameState.upgrade_level("blade"), 2)
	var engine := 1.0 + 0.18 * GameState.upgrade_level("motor")
	var deck_width := blade_width + 0.1
	Models.place(_mower, "mower_deck_%d" % level, Vector3.ZERO, 1.0)
	Models.place(_mower, "mower_handle", Vector3.ZERO, 1.0)
	Models.place(_mower, "mower_engine", Vector3(0.0, 0.44, -0.06), engine)
	_engine_top = 0.44 + 0.3 * engine
	_engine_cap = Models.place(_mower, "mower_cap", Vector3(0.0, _engine_top, -0.06), engine, 0.0, false)
	_engine_cap.set_meta("no_bake", true)
	_bag = Models.place(_mower, "mower_bag", Vector3(0.0, 0.25, 0.36), 1.0, 0.0, false)
	_bag.set_meta("no_bake", true)
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.24, 0.26]:
			var wheel := Models.place(_mower, "mower_wheel", Vector3((deck_width * 0.5 + 0.05) * side, WHEEL_RADIUS, z),
					1.0, 0.0, false)
			wheel.set_meta("no_bake", true)
			_wheels.append(wheel)

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
	_exhaust.position = Vector3(0.14, 0.44 + 0.27 * engine, 0.2)
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
