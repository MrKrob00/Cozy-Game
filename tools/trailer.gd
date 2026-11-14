extends SceneTree
## Снимает трейлер игры: сценарий ведёт героя, камеру и подписи покадрово.
##
## Запуск (нужен экран или xvfb; кадры пишет сам Godot):
##   tools/make_trailer.sh
## Он запускает этот сценарий с записью кадров (--write-movie) и собирает
## кадры и звук в docs/trailer.mp4.
##
## Построение по советам монтажёров трейлеров (Derek Lieu): геймплей с первой
## секунды и сразу «крючок» — приятная полоса в высокой траве; затем понятно,
## что это за игра (цикл покоса); дальше содержимое по нарастанию: находки,
## новые участки, деревня, улучшения, праздник; название — в самом конце.
## «Показывай мечту, а не работу»: никаких меню.
##
## Игровые классы не используются как типы: скрипт компилируется раньше,
## чем регистрируются автозагрузки.

const FPS := 30.0
const CUT_LENGTH := 0.4

var _village: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _hud: CanvasLayer
var _state: Node
var _terrain: Node
var _placeholder: GDScript
var _juice: GDScript
var _fields: Array = []
var _caption: PanelContainer
var _caption_label: Label
var _overlay: CanvasLayer
# Маршрут героя: точки (x, z) и пройденный по нему путь.
var _route := PackedVector2Array()
var _route_at := 0.0
var _route_length := 0.0


func _initialize() -> void:
	_run.call_deferred()


func frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	_state = root.get_node("GameState")
	# Как при запекании карты: сохранение игрока трейлер не трогает.
	Engine.set_meta("baking_map", true)
	_state.clear()
	_state.title_seen = true
	_state.graphics_quality = 2
	# Трейлер на английском: и подписи, и интерфейс игры.
	_state.language = "en"
	_state.apply_language()
	_state.music_enabled = true
	_state.sound_enabled = true
	change_scene_to_file("res://scenes/village.tscn")
	await frames(12)
	_village = current_scene
	_player = get_first_node_in_group("player")
	_camera = _village.get_node("Camera")
	_hud = _village.get_node("HUD")
	_terrain = _village.get_node("Terrain")
	_placeholder = load("res://scripts/placeholder.gd")
	_juice = load("res://scripts/juice.gd")
	_fields = get_nodes_in_group("mow_field")
	_hud.get_node("%HintLabel").visible = false
	# Окно завершения участка в трейлере не показываем: только игра.
	_hud.get_node("%Completion").modulate.a = 0.0
	_hud.get_node("%Completion").mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Всплывающие подсказки игры идут с задержкой и в монтаже мешали бы
	# подписям трейлера; кнопку действия тоже прячем.
	# (У всплывающей панели игра сама анимирует modulate, поэтому гасим self_modulate.)
	_hud.get_node("%Toast").self_modulate.a = 0.0
	_hud.get_node("%ToastLabel").self_modulate.a = 0.0
	_hud.get_node("%ActionButton").self_modulate.a = 0.0
	_hud.get_node("%ActionButton").add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_player.set_physics_process(false)
	# Калитку трейлер показывает сам, в своём кадре.
	_hud.auto_reveal = false
	_build_overlay()
	var yard: Node3D = _village.get_node("Yard")
	var garden: Node3D = _village.get_node("Garden")
	var square: Node3D = _village.get_node("Square")
	var orchard: Node3D = _village.get_node("Orchard")

	# Заготовка: пара полос уже скошена, герой — в начале третьей.
	var lanes: Array[float] = [0.6, 1.35, 2.1, 2.85, 3.6, 4.35, 5.1, 5.85]
	_set_route(_serpentine(yard, [lanes[0], lanes[1]], 5.6, -5.6))
	while _advance(40.0, yard):
		pass
	_set_route(_serpentine(yard, lanes.slice(2), 5.6, -5.6))
	_advance(0.01, yard)
	_set_hud(false)
	_camera.set_process(false)
	_chase_camera(Vector3(2.9, 1.5, -4.6), Vector3(0.0, 0.75, -0.7))
	await frames(40)
	print("TRAILER_START ", Engine.get_frames_drawn())

	# 1. Крючок: косилка идёт сквозь высокую траву, за ней ровная полоса.
	for i in 96:
		_advance(2.7, yard)
		var swing := i / 96.0
		_chase_camera(Vector3(2.9 - 1.0 * swing, 1.5 + 0.7 * swing, -4.6 + 0.4 * swing), Vector3(0.0, 0.75, -0.7))
		if i == 14:
			_say("Turn the overgrown into a cozy garden")
		await process_frame

	# 2. Цикл покоса: вид как в игре, двор покрывается полосами, находки.
	_say("")
	_set_hud(true)
	_follow_camera(1)
	for i in 138:
		_advance(8.5, yard)
		if i == 20:
			_say("Mow it stripe by stripe")
		if i == 84:
			_say("Find lost things in the grass")
		await process_frame

	# 3. Двор выкошен: конфетти, облёт, награда.
	_say("")
	_player.set("_current_speed", 0.0)
	yard.field.mow(yard.field.global_position, Vector3.FORWARD, 40.0, 40.0)
	await frames(8)
	_say("The yard is mowed!")
	await frames(76)

	# 4. Камера едет к новой калитке, и она открывается.
	_hud.call("_reveal_next_plot")
	await frames(16)
	_say("Open up new places")
	await frames(88)

	# 5. Дорога через деревню по стрелкам.
	_say("")
	_follow_camera(2)
	_set_route(PackedVector2Array([Vector2(0.0, 9.8), Vector2(0.0, 19.5), Vector2(-2.6, 22.6),
			Vector2(-4.2, 25.4), Vector2(-9.0, 26.0), Vector2(-15.4, 26.0)]))
	_teleport()
	for i in 92:
		_advance(5.2, null)
		if i == 12:
			_say("A little village wakes up")
		await process_frame

	# 6а. Улучшения: новая косилка в саду бабушки.
	_say("")
	_complete_silently(yard)
	garden.reveal()
	_state.upgrade_levels = {"blade": 2, "bag": 1, "motor": 2}
	_state.upgrades_changed.emit()
	_set_hud(false)
	_set_route(_serpentine(garden, [-1.2, -0.2], 5.8, -5.8))
	_teleport()
	_camera.set_process(false)
	for i in 46:
		_advance(3.0, garden)
		_chase_camera(Vector3(-3.0, 1.9, -4.2), Vector3(0.0, 0.75, -0.6))
		if i == 6:
			_say("Upgrade your mower")
		await process_frame

	# 6б. Площадь: бурьян и широкий нож.
	_say("")
	_complete_silently(garden)
	square.fence.set_gate_open(true, false)
	square.fence.call("_update_sign", square)
	_premow(square, 0.45)
	_set_hud(true)
	_set_route(_serpentine(square, [7.0, 8.0, 9.0], 8.4, 2.6))
	_teleport()
	_follow_camera(1)
	for i in 44:
		_advance(5.5, square)
		if i == 6:
			_say("Tame the weeds")
		await process_frame

	# 6в. Фруктовый сад: деревья, пруд, лягушки.
	_say("")
	_complete_silently(square)
	square.get_node("Fountain").set_repaired(false)
	orchard.fence.set_gate_open(true, false)
	orchard.fence.call("_update_sign", orchard)
	_premow(orchard, 0.5)
	_set_route(_serpentine(orchard, [-7.4, -6.4, -5.4], 2.6, -8.6))
	_teleport()
	_follow_camera(2)
	for i in 44:
		_advance(6.0, orchard)
		if i == 6:
			_say("Every garden has its own charm")
		await process_frame

	# 7. Финал: праздник в деревне и название.
	_say("")
	_complete_silently(orchard)
	_set_hud(false)
	_set_route(PackedVector2Array([Vector2(1.5, 29.6), Vector2(1.5, 29.0)]))
	_teleport()
	_player.set("_current_speed", 0.0)
	_state.set_flag("festival")
	_village.festival_started.emit(false)
	_camera.set_process(true)
	_camera.set("_focus", Vector3(0.0, 1.0, 25.0))
	_camera.zoom_index = 2
	_camera.set("_distance", 24.0)
	_camera.call("set_menu", true)
	_camera.set("_distance_offset", 3.0)
	_camera.set("_yaw_offset", -24.0)
	for i in 3:
		_juice.confetti(_village, Vector3(-4.0 + i * 4.0, 2.6, 24.0 + (i % 2) * 3.0), 70)
	await frames(26)
	_show_title()
	for i in 3:
		_juice.confetti(_village, Vector3(-3.0 + i * 3.0, 3.0, 27.0), 60)
	await frames(94)
	print("TRAILER_END ", Engine.get_frames_drawn())
	_state.clear()
	_state.graphics_quality = -1
	_state.language = ""
	quit()


# --- Герой ---

func _set_route(points: PackedVector2Array) -> void:
	_route = points
	_route_at = 0.0
	_route_length = 0.0
	for i in points.size() - 1:
		_route_length += points[i].distance_to(points[i + 1])


# Точка маршрута на расстоянии along от начала и направление в ней.
func _route_point(along: float) -> Array:
	var left := clampf(along, 0.0, _route_length)
	for i in _route.size() - 1:
		var length := _route[i].distance_to(_route[i + 1])
		if left <= length or i == _route.size() - 2:
			var direction := (_route[i + 1] - _route[i]).normalized()
			return [_route[i] + direction * minf(left, length), direction]
		left -= length
	return [_route[0], Vector2(0.0, -1.0)]


# Ставит героя в начало маршрута без плавного доворота (смена кадра).
func _teleport() -> void:
	var start := _route_point(0.0)
	var at: Vector2 = start[0]
	var direction: Vector2 = start[1]
	_player.global_position = Vector3(at.x, _terrain.height_at(at), at.y)
	_player.rotation = Vector3(0.0, atan2(-direction.x, -direction.y), 0.0)
	_camera.set("_focus", _player.global_position)
	_camera.set("_ahead", Vector3.ZERO)


# Двигает героя по маршруту на один кадр и косит под ножом. Возвращает
# false, когда маршрут пройден.
func _advance(speed: float, plot) -> bool:
	var step := speed / FPS
	# Быстрый проход делится на шаги не длиннее ножа, чтобы не было пропусков.
	var parts := maxi(int(ceilf(step / (CUT_LENGTH * 0.7))), 1)
	var cutting := false
	for part in parts:
		_route_at += step / parts
		var point := _route_point(_route_at)
		var at: Vector2 = point[0]
		var direction: Vector2 = point[1]
		var yaw := atan2(-direction.x, -direction.y)
		_player.rotation.y = lerp_angle(_player.rotation.y, yaw, 0.45 if parts == 1 else 1.0)
		# Поворот — вокруг ножа, как в игре: точка маршрута — это нож.
		var forward := -_player.global_basis.z
		var body := Vector3(at.x, 0.0, at.y) - forward * 0.95
		_player.global_position = Vector3(body.x, _terrain.height_at(Vector2(body.x, body.z)), body.z)
		if plot:
			var units: float = plot.field.mow(_player.get_blade_position(), forward, _player.get_cut_width(),
					CUT_LENGTH, true)
			if units > 0.0:
				cutting = true
				_state.add_grass(units * 0.4)
				if _state.bag_fill > _state.bag_capacity * 0.8:
					_state.empty_bag()
	var pusher: Vector3 = _player.global_position - _player.global_basis.z * 0.57
	for field in _fields:
		field.set_pusher_position(pusher)
	_placeholder.set_pusher(pusher)
	_player.set("_current_speed", minf(speed, 3.4))
	_player.set("_cutting", cutting)
	var clippings = _player.get("_clippings")
	if is_instance_valid(clippings):
		clippings.emitting = cutting
	_player.call("_update_interaction", 1.0 / FPS)
	return _route_at < _route_length


# Маршрут «змейкой» по участку: полосы на местных x (lanes) между местными
# z from и to, развороты дугой.
func _serpentine(plot: Node3D, lanes: Array, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in lanes.size():
		var start := from if i % 2 == 0 else to
		var end := to if i % 2 == 0 else from
		points.append(_local(plot, lanes[i], start))
		points.append(_local(plot, lanes[i], end))
		if i < lanes.size() - 1:
			var middle: float = (lanes[i] + lanes[i + 1]) * 0.5
			var radius: float = absf(lanes[i + 1] - lanes[i]) * 0.5
			var out := signf(end - start)
			for k in range(1, 6):
				var angle := PI * k / 6.0
				points.append(_local(plot, middle - cos(angle) * (lanes[i + 1] - lanes[i]) * 0.5,
						end + out * sin(angle) * radius))
	return points


func _local(plot: Node3D, x: float, z: float) -> Vector2:
	var world := plot.to_global(Vector3(x, 0.0, z))
	return Vector2(world.x, world.z)


# Участок считается выкошенным без торжества (смена кадра в монтаже).
func _complete_silently(plot: Node3D) -> void:
	var state: Dictionary = plot.get("_state")
	state["completed"] = true
	state["tidy"] = true
	state["milestones"] = [25, 50, 75]
	plot.field.mow(plot.field.global_position, Vector3.FORWARD, 80.0, 80.0)
	plot.call("_light_up")
	plot.fence.call("_update_sign", plot)


# Часть участка уже скошена полосами (share — доля ширины), без наград.
func _premow(plot: Node3D, share: float) -> void:
	var state: Dictionary = plot.get("_state")
	state["milestones"] = [25, 50, 75]
	var half: Vector2 = plot.field.size * 0.5
	var x := -half.x + 0.4
	var lane := 0
	while x < -half.x + plot.field.size.x * share:
		var z := -half.y
		while z < half.y:
			var forward: Vector3 = plot.global_basis.z * (1.0 if lane % 2 == 0 else -1.0)
			plot.field.mow(plot.to_global(Vector3(x, 0.0, z)), forward, 1.1, 0.5, false)
			z += 0.35
		x += 1.05
		lane += 1


# --- Камера ---

# Камера рядом с героем: offset и look — в его координатах (−Z вперёд).
func _chase_camera(offset: Vector3, look: Vector3) -> void:
	var basis := _player.global_basis
	var origin := _player.global_position
	_camera.global_position = origin + basis * offset
	_camera.look_at(origin + basis * look, Vector3.UP)


# Обычная игровая камера на ступени масштаба zoom.
func _follow_camera(zoom: int) -> void:
	_camera.zoom_index = zoom
	_camera.set("_distance", _camera.zoom_distances[zoom])
	_camera.set("_focus", _player.global_position)
	_camera.set("_ahead", Vector3.ZERO)
	_camera.set_process(true)


# --- Подписи ---

func _set_hud(shown: bool) -> void:
	_hud.get_node("%Margin").visible = shown


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 60
	root.add_child(_overlay)
	_caption = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.96, 0.86, 0.96)
	box.set_corner_radius_all(28)
	box.content_margin_left = 44.0
	box.content_margin_right = 44.0
	box.content_margin_top = 18.0
	box.content_margin_bottom = 22.0
	box.shadow_color = Color(0.2, 0.14, 0.08, 0.35)
	box.shadow_size = 10
	_caption.add_theme_stylebox_override("panel", box)
	_caption_label = Label.new()
	_caption_label.add_theme_font_size_override("font_size", 58)
	_caption_label.add_theme_color_override("font_color", Color(0.27, 0.22, 0.17))
	_caption.add_child(_caption_label)
	_caption.visible = false
	_overlay.add_child(_caption)


# Подпись внизу экрана; пустая строка её убирает.
func _say(text: String) -> void:
	if text == "":
		_caption.visible = false
		return
	_caption_label.text = text
	_caption.visible = true
	_caption.reset_size()
	var screen := root.get_visible_rect().size
	_caption.position = Vector2((screen.x - _caption.size.x) * 0.5, screen.y - _caption.size.y - 70.0)
	_caption.pivot_offset = _caption.size * 0.5
	_caption.scale = Vector2.ONE * 0.6
	var tween := _caption.create_tween()
	tween.tween_property(_caption, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Название игры и слоган в конце.
func _show_title() -> void:
	var screen := root.get_visible_rect().size
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	_overlay.add_child(column)
	var title := Label.new()
	title.text = "Cozy Grass Cut"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 170)
	title.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	title.add_theme_color_override("font_outline_color", Color(0.33, 0.24, 0.12))
	title.add_theme_constant_override("outline_size", 40)
	column.add_child(title)
	var tagline := Label.new()
	tagline.text = "One cozy stripe at a time"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 64)
	tagline.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	tagline.add_theme_color_override("font_outline_color", Color(0.33, 0.24, 0.12))
	tagline.add_theme_constant_override("outline_size", 22)
	column.add_child(tagline)
	title.pivot_offset = Vector2(screen.x * 0.5, 110.0)
	title.scale = Vector2.ONE * 1.6
	title.modulate.a = 0.0
	tagline.modulate.a = 0.0
	var tween := title.create_tween()
	tween.tween_property(title, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(tagline, "modulate:a", 1.0, 0.35)
