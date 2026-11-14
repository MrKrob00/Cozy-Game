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
	# Проверки сверяют русские тексты; английский проверяется отдельно.
	game_state.language = "ru"
	game_state.apply_language()
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
	var fixed_stick = current_scene.get_node("HUD/VirtualJoystick")
	var stick_at: Vector2 = fixed_stick.global_position + fixed_stick.size * fixed_stick.initial_offset_ratio
	touch(0, stick_at, true)
	await frames(2)
	drag(0, stick_at + Vector2(130, 0), Vector2(130, 0))
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
	touch(0, stick_at + Vector2(130, 0), false)
	await frames(20)
	check(move_vector() == Vector2.ZERO, "joystick released")

	# 3b. Сенсорные схемы: джойстик идёт за пальцем, закреплён слева или «вести пальцем».
	var hud_node = current_scene.get_node("HUD")
	var stick = hud_node.get_node("VirtualJoystick")
	var pad = hud_node.get_node("TouchPad")
	var touch_screen := DisplayServer.is_touchscreen_available()
	check(stick.joystick_mode == 0 and stick.visible and not pad.visible, "by default the joystick is fixed in place")
	check((stick.visibility_mode == 0) == touch_screen, "it is always shown on a touch screen and hidden on a computer")
	check(stick.anchor_right < 0.5 and stick.size.x < root.get_visible_rect().size.x * 0.5, "the fixed joystick listens only on the left of the screen")
	game_state.set_touch_controls(1)
	check(stick.joystick_mode == 2 and stick.visibility_mode == 1 and stick.size.x > root.get_visible_rect().size.x * 0.9, "second scheme: a joystick that follows the finger anywhere")
	game_state.set_touch_controls(2)
	check(not stick.visible and pad.visible and player.touch_pad == pad, "third scheme: lead with a finger")
	player.global_position = Vector3(0, 0, 3.0)
	player.rotation = Vector3.ZERO
	await frames(40)
	var finger_goal: Vector3 = player.global_position + Vector3(4.0, 0, 0)
	var finger: Vector2 = camera.unproject_position(finger_goal)
	touch(0, finger, true)
	await frames(2)
	check(pad.held, "the touch pad holds the finger")
	await frames(100)
	print("finger: player at ", player.global_position)
	check(player.global_position.x > 1.2 and absf(player.global_position.z - 3.0) < 1.6, "the mower drives toward the finger")
	touch(0, finger, false)
	await frames(30)
	check(not pad.held and player.velocity.length() < 0.05, "lifting the finger stops the mower")
	game_state.set_touch_controls(0)
	check(stick.joystick_mode == 0 and stick.visible and not pad.visible and player.touch_pad == null, "back to the fixed joystick")

	# 3c. Разворот: направление за спиной — косилка доворачивает в одну сторону.
	player.global_position = Vector3(0, 0, 3.0)
	player.rotation = Vector3.ZERO
	await frames(30)
	Input.action_press("move_down"); Input.action_press("move_left")
	var turned := 0.0
	var reversals := 0
	var last_yaw: float = player.rotation.y
	for i in 80:
		await physics_frame
		var step: float = angle_difference(last_yaw, player.rotation.y)
		if absf(step) > 0.0001 and turned != 0.0 and signf(step) != signf(turned):
			reversals += 1
		turned += step
		last_yaw = player.rotation.y
	Input.action_release("move_down"); Input.action_release("move_left")
	await frames(20)
	print("u-turn: turned %.2f rad, reversals %d" % [turned, reversals])
	check(absf(absf(turned) - PI) < 0.25 and reversals == 0, "a U-turn goes one way and finishes in about a second")

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

	# 6b. Поворот вокруг косилки, покос до колёс, скорость на улице.
	player.global_position = Vector3(0, 0, 3.0)
	player.rotation = Vector3.ZERO
	await frames(3)
	var blade_before: Vector3 = player.get_blade_position()
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_right")
	var blade_shift: float = Vector2(player.get_blade_position().x - blade_before.x, player.get_blade_position().z - blade_before.z).length()
	var body_shift: float = Vector2(player.global_position.x, player.global_position.z - 3.0).length()
	print("turn: blade moved %.2f, body moved %.2f" % [blade_shift, body_shift])
	check(blade_shift < body_shift, "turning pivots around the mower, not the character")
	check(is_equal_approx(player.get_cut_width(), player.blade_width + 0.18), "cut reaches the middle of the wheels")
	# Дорога от калитки двора к поляне идёт на +Z и поднимается.
	player.global_position = Vector3(0, 0, 10.5)
	player.rotation = Vector3(0, PI, 0)
	await frames(5)
	Input.action_press("move_down"); Input.action_press("move_left")
	await frames(90)
	var road_speed: float = player.velocity.length()
	Input.action_release("move_down"); Input.action_release("move_left")
	print("road speed %.2f" % road_speed)
	check(road_speed > player.speed * 1.3, "the mower rolls faster on the street")
	check(player.global_position.y > 0.2, "the road climbs toward the next plots")
	player.global_position = Vector3(0, 0, 3.0)
	await frames(30)

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
	check(is_equal_approx(root.scaling_3d_scale, 0.75) and root.msaa_3d == Viewport.MSAA_DISABLED, "low quality lowers 3D resolution and turns MSAA off")
	check(field.get_progress() > 0.001, "mowing progress survives the grass rebuild")
	game_state.set_graphics_quality(2)
	await frames(3)
	check(count_grass.call() == high_grass and is_equal_approx(root.scaling_3d_scale, 1.0), "high quality restores the grass")
	game_state.set_show_fps(true)
	check(hud.get_node("%FpsLabel").visible, "FPS counter can be turned on")
	game_state.set_show_fps(false)

	# 9. Рендер: детали склеены, тени — двойники, трава вдали реже.
	var shadows = current_scene.get_node("Shadows")
	# Трава перестраивалась при смене качества: ждём обновления детализации.
	await frames(30)
	var loose := 0
	for mesh in current_scene.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override is ShaderMaterial and mesh.material_override.shader.resource_path.contains("toon") \
				and mesh.material_override.get_shader_parameter("albedo") != Color.WHITE \
				and not mesh.has_meta("no_bake") and mesh.mesh is PrimitiveMesh:
			loose += 1
	print("unbaked parts: %d, casters: %d, moving casters: %d" % [loose, shadows.caster_count(), shadows.dynamic_count()])
	check(loose == 0, "every static part is baked into a merged model")
	check(shadows.caster_count() > 60 and shadows.dynamic_count() >= 10, "baked models cast shadows through proxies")
	check(not current_scene.get_node("Sun").visible, "the engine light is off: materials light themselves")
	var far_chunk = null
	var near_chunk = null
	for chunk in current_scene.get_node("Orchard/MowField").find_children("Grass_*", "MultiMeshInstance3D", false, false):
		far_chunk = chunk
	for chunk in field.find_children("Grass_*", "MultiMeshInstance3D", false, false):
		if chunk.multimesh.visible_instance_count == -1:
			near_chunk = chunk
	check(near_chunk != null, "grass next to the player is drawn in full")
	check(far_chunk != null and far_chunk.multimesh.visible_instance_count > 0 \
			and far_chunk.multimesh.visible_instance_count < far_chunk.multimesh.instance_count * 0.5,
			"far grass draws only part of its clumps")

	# 10. Звук: мотора нет, музыка играет.
	var sfx = root.get_node("Sfx")
	check(sfx.call("_variants", "mower_loop").is_empty() and sfx.call("_variants", "swish").is_empty(), "the mower is silent: no motor loop, no cutting sound")
	check(sfx.get("_playlist").size() == 4 and sfx.current_track() != "", "music playlist is playing")
	game_state.set_music_enabled(false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "music can be muted on its own")
	game_state.set_music_enabled(true)

	# 8. Безопасная область: обычный вырез учитывается, неправдоподобные значения — нет.
	var notch: Array = hud.safe_insets(Vector2(2400, 1080), Rect2(90, 0, 2310, 1080), Vector2(2400, 1080))
	check(notch == [90.0, 0.0, 0.0, 0.0], "notch on the left becomes a left margin")
	var scaled: Array = hud.safe_insets(Vector2(1200, 540), Rect2(0, 0, 1150, 540), Vector2(2400, 1080))
	check(scaled == [0.0, 0.0, 100.0, 0.0], "margins are converted to interface units")
	var wrong: Array = hud.safe_insets(Vector2(2400, 1080), Rect2(0, 0, 1080, 2400), Vector2(2400, 1080))
	check(wrong == [0.0, 0.0, 0.0, 0.0], "safe area for the wrong orientation is ignored")
	check(hud.get_node("%ActionButton").get_parent() == hud.get_node("%Margin"), "action button sits inside the safe margins")

	# 11. Язык: у каждой русской строки игры есть английский перевод.
	var strings: Dictionary = load("res://scripts/strings_en.gd").MESSAGES
	var translate: GDScript = load("res://scripts/l.gd")
	var cyrillic := RegEx.create_from_string("[А-Яа-яЁё]")
	var literal := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var missing: Array[String] = []
	var sources: Array[String] = []
	for file in DirAccess.get_files_at("res://scripts"):
		if file.ends_with(".gd") and file != "strings_en.gd":
			sources.append("res://scripts/" + file)
	for file in ["hud.tscn", "plots/yard.tscn", "plots/garden.tscn", "plots/square.tscn", "plots/orchard.tscn"]:
		sources.append("res://scenes/" + file)
	for path in sources:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var code := line.strip_edges()
			# Комментарии, предупреждения в журнал и названия групп инспектора не переводятся.
			if code.begins_with("#") or code.contains("push_warning") or code.begins_with("@export_group"):
				continue
			for found in literal.search_all(line):
				var text := found.get_string(1).c_unescape()
				if cyrillic.search(text) and not strings.has(text) and not text in missing:
					missing.append(text)
	if not missing.is_empty():
		print("no English for: ", missing)
	check(missing.is_empty(), "every Russian string of the game has an English translation (%d checked)" % strings.size())
	var broken: Array[String] = []
	for source: String in strings:
		if source.count("%") != (strings[source] as String).count("%"):
			broken.append(source)
	check(broken.is_empty(), "translations keep the same placeholders %s" % str(broken))

	# 12. Переключение языка: интерфейс, участки и подписи становятся английскими.
	check(game_state.get_language() == "ru" and translate.t("Играть") == "Играть", "Russian strings are shown as written")
	game_state.set_language("en")
	check(translate.t("Играть") == "Play" and translate.t("Монеты: %d") % 5 == "Coins: 5", "English strings come from the dictionary")
	reload_current_scene()
	await frames(8)
	var english_hud = current_scene.get_node("HUD")
	check(english_hud.get_node("%CoinsLabel").text == "Coins: 0" and english_hud.get_node("%ProgressLabel").text.begins_with("Yard:"), "the HUD is in English after the switch")
	check(english_hud.get_node("%LanguageButton").text == "Language: English", "the language button names the language")
	check(english_hud.get_node("%TitleLabel").text == "Cozy Grass Cut", "the title screen carries the game's name")
	var english_yard = current_scene.get_node("Yard")
	check(english_yard.fence.get("_sign_label").text == "Yard", "plot signs are in English")
	check(english_yard.get_stamps()[0]["title"] == "Mowed", "stamps are in English")
	var english_toasts: Array[String] = []
	game_state.toast_requested.connect(func(t): english_toasts.append(t))
	game_state.toast("Мешок полон — отвезите траву в компостный ящик")
	check(english_toasts == ["The bag is full — take the grass to the compost bin"], "messages are translated where they are shown")
	english_hud.call("_switch_language")
	await frames(8)
	check(game_state.get_language() == "ru" and current_scene.get_node("HUD").get_node("%CoinsLabel").text == "Монеты: 0", "the button switches back to Russian and reloads the scene")
	game_state.language = ""

	game_state.clear()
	game_state.graphics_quality = -1
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
