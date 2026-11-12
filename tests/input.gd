extends SceneTree
# Проверка ввода и настроек: действия InputMap, клавиатура, сенсорный джойстик,
# щипок, колесо мыши, удержание мыши, границы участка, качество графики,
# безопасная область экрана.
#
# Запуск из папки проекта:
#   godot --headless --path . --fixed-fps 60 --script tests/input.gd
#
# Игровые классы здесь нарочно не используются как типы: скрипт компилируется
# раньше, чем регистрируется автозагрузка GameState.
# Тест стирает сохранение (user://save.dat).

var failures := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Переводит координаты интерфейса (база 1920×1080) в координаты окна.
func to_window(point: Vector2) -> Vector2:
	return point * Vector2(root.size) / root.get_visible_rect().size


func touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = to_window(at)
	event.pressed = pressed
	Input.parse_input_event(event)


func drag(index: int, at: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to_window(at)
	event.relative = to_window(relative)
	Input.parse_input_event(event)


func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_state := root.get_node("GameState")
	game_state.clear()
	for action: String in ["move_left", "move_right", "move_up", "move_down",
			"interact", "zoom_in", "zoom_out", "pause"]:
		check(InputMap.has_action(action) and InputMap.action_get_events(action).size() >= 2,
				"action %s has events" % action)

	change_scene_to_file("res://scenes/village.tscn")
	await frames(5)
	var field = get_first_node_in_group("mow_field")
	var player = get_first_node_in_group("player")
	var camera = current_scene.get_node("Camera")
	var pinch = get_first_node_in_group("pinch_zoom")
	check(field != null and player != null and camera != null, "field, player, camera present")
	check(is_zero_approx(field.get_progress()), "progress starts at 0")

	# 1. Клавиатура: 2 секунды «вверх».
	var start: Vector3 = player.global_position
	Input.action_press("move_up")
	await frames(120)
	Input.action_release("move_up")
	await frames(30)
	var moved: Vector3 = player.global_position - start
	check(moved.length() > 2.5, "player moved with keyboard action")
	check(moved.x < -1.0 and moved.z < -1.0, "movement is camera-relative (into the screen)")
	check(field.get_progress() > 0.001 and game_state.bag_fill > 1.0, "grass was cut into the bag")
	check(player.velocity.length() < 0.05, "player stops when input released")
	check(field.get_height_at(player.global_position - player.global_basis.z * 0.95) == 0.0,
			"grass under blade is cut")

	# 2. Сенсорный джойстик: касание и перетаскивание вправо.
	var before: Vector3 = player.global_position
	touch(0, Vector2(400, 700), true)
	await frames(2)
	drag(0, Vector2(580, 700), Vector2(180, 0))
	await frames(3)
	check(move_vector().x > 0.5 and absf(move_vector().y) < 0.2, "touch joystick drives move actions")
	await frames(90)
	check((player.global_position - before).length() > 1.5, "player moved with touch joystick")

	# 3. Щипок: второй палец, разводим — камера приближается, косилка стоит.
	var zoom_before: int = camera.zoom_index
	touch(1, Vector2(700, 700), true)
	await frames(2)
	check(pinch.active, "pinch active with two fingers")
	drag(1, Vector2(1100, 700), Vector2(400, 0))
	await frames(2)
	check(camera.zoom_index == zoom_before - 1, "pinch out zooms in")
	await frames(30)
	check(player.velocity.length() < 0.5, "player halts while pinching")
	touch(1, Vector2(1100, 700), false)
	touch(0, Vector2(580, 700), false)
	await frames(20)
	check(move_vector() == Vector2.ZERO, "joystick released")

	# 4. Колесо мыши.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.device = 0
	var zoom: int = camera.zoom_index
	Input.parse_input_event(wheel)
	await frames(2)
	check(camera.zoom_index == zoom + 1, "mouse wheel zooms out")

	# 5. Мышь: зажата левая кнопка.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.device = 0
	click.position = to_window(Vector2(300, 500))
	Input.parse_input_event(click)
	await frames(2)
	check(player.get("_mouse_held") == true, "mouse hold registered through HUD")
	click.pressed = false
	Input.parse_input_event(click)

	# 6. Границы: держим «влево» 15 секунд, игрок остаётся там, где можно ходить.
	Input.action_press("move_left")
	await frames(900)
	Input.action_release("move_left")
	var at := Vector2(player.global_position.x, player.global_position.z)
	var inside := false
	for area in get_nodes_in_group("walk_area"):
		for rect: Rect2 in area.get_walk_rects():
			if rect.grow(0.05).has_point(at):
				inside = true
	check(inside, "player stays inside walkable areas")

	# 7. Качество графики: меньше травы и ниже разрешение 3D на низком.
	var hud = current_scene.get_node("HUD")
	var count_grass := func() -> int:
		var total := 0
		for child in field.get_children():
			if child is MultiMeshInstance3D:
				total += child.multimesh.instance_count
		return total
	check(game_state.get_quality() == 2 and is_equal_approx(root.scaling_3d_scale, 1.0), "desktop starts on high quality")
	var high_grass: int = count_grass.call()
	game_state.set_graphics_quality(0)
	await frames(3)
	var low_grass: int = count_grass.call()
	print("grass clumps in the yard: high=%d low=%d" % [high_grass, low_grass])
	check(low_grass < high_grass * 0.5 and low_grass > high_grass * 0.3, "low quality draws about 40 % of the grass")
	check(is_equal_approx(root.scaling_3d_scale, 0.7) and root.msaa_3d == Viewport.MSAA_DISABLED, "low quality lowers 3D resolution and turns MSAA off")
	check(field.get_progress() > 0.001, "mowing progress survives the grass rebuild")
	game_state.set_graphics_quality(2)
	await frames(3)
	check(count_grass.call() == high_grass and is_equal_approx(root.scaling_3d_scale, 1.0), "high quality restores the grass")
	game_state.set_show_fps(true)
	check(hud.get_node("%FpsLabel").visible, "FPS counter can be turned on")
	game_state.set_show_fps(false)

	# 8. Безопасная область: обычный вырез учитывается, неправдоподобные значения — нет.
	var notch: Array = hud.safe_insets(Vector2(2400, 1080), Rect2(90, 0, 2310, 1080), Vector2(2400, 1080))
	check(notch == [90.0, 0.0, 0.0, 0.0], "notch on the left becomes a left margin")
	var scaled: Array = hud.safe_insets(Vector2(1200, 540), Rect2(0, 0, 1150, 540), Vector2(2400, 1080))
	check(scaled == [0.0, 0.0, 100.0, 0.0], "margins are converted to interface units")
	var wrong: Array = hud.safe_insets(Vector2(2400, 1080), Rect2(0, 0, 1080, 2400), Vector2(2400, 1080))
	check(wrong == [0.0, 0.0, 0.0, 0.0], "safe area for the wrong orientation is ignored")
	check(hud.get_node("%ActionButton").get_parent() == hud.get_node("%Margin"), "action button sits inside the safe margins")

	game_state.clear()
	game_state.graphics_quality = -1
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
