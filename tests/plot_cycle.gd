extends SceneTree
# Проверка полного цикла участка «Двор»: мешок, компост, находка, ёжик,
# завершение, пауза, сохранение и загрузка.
#
# Запуск из папки проекта:
#   godot --headless --path . --fixed-fps 60 --script tests/plot_cycle.gd
#
# Игровые классы здесь нарочно не используются как типы: скрипт компилируется
# раньше, чем регистрируется автозагрузка GameState.
# Тест стирает сохранение (user://save.dat).

var failures := 0
var gs: Node

func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func hold(action: String, n: int) -> void:
	Input.action_press(action)
	await frames(n)
	Input.action_release(action)
	await frames(20)

func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(2)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	gs = root.get_node("GameState")
	gs.clear()
	change_scene_to_file("res://scenes/yard.tscn")
	await frames(5)
	var plot = get_first_node_in_group("plot")
	var field = plot.field
	var player = get_first_node_in_group("player")
	var hud := current_scene.get_node("HUD")
	var toasts: Array[String] = []
	gs.toast_requested.connect(func(t): toasts.append(t))
	var mowable: int = field.get("_mowable_cells")
	print("mowable cells=%d (%.1f m2)" % [mowable, mowable * 0.125 * 0.125])
	check(mowable > 10000 and mowable < 10752, "field has blocked cells under bench and tree")
	check(get_nodes_in_group("find").size() == 3 and get_nodes_in_group("animal").size() == 1, "3 finds and 1 animal")
	check(plot.get_stamps().size() == 4, "4 stamps listed")
	check(not hud.get_node("%ActionButton").visible, "action button hidden at start")

	# 1. Покос наполняет мешок.
	await hold("move_up", 180)
	print("bag=%.1f progress=%.3f pos=%s" % [gs.bag_fill, field.get_progress(), player.global_position])
	check(gs.bag_fill > 3.0, "mowing fills the bag")
	check(absf(hud.get_node("%BagBar").value - gs.bag_fill) < 0.02, "HUD bag bar follows bag")

	# 2. Полный мешок останавливает нож.
	gs.add_grass(1000.0)
	check(gs.is_bag_full() and gs.bag_fill == gs.bag_capacity, "bag clamps at capacity")
	check(toasts.any(func(t): return t.begins_with("Мешок полон")), "bag full toast")
	var before: float = field.get_progress()
	await hold("move_up", 90)
	check(is_equal_approx(field.get_progress(), before), "full bag stops cutting")

	# 3. Компостный ящик.
	var bin = current_scene.get_node("CompostBin")
	check(bin.get("_arrow").visible, "arrow shown over compost bin when bag is full")
	player.global_position = Vector3(3.3, 0, 4.6)
	player.rotation = Vector3(0, PI, 0)  # лицом к +Z, к ящику
	await hold("move_down", 1)
	Input.action_press("move_down"); Input.action_press("move_left")  # на экране вниз-влево = +Z
	await frames(120)
	Input.action_release("move_down"); Input.action_release("move_left")
	await frames(20)
	print("at bin: pos=%s target=%s" % [player.global_position, player.interaction_target])
	check(player.interaction_target == bin, "compost bin becomes interaction target")
	check(player.global_position.z < 6.2, "mower is stopped by the bin")
	check(hud.get_node("%ActionButton").visible and "Высыпать" in hud.get_node("%ActionButton").text, "action button shows prompt")
	await press("interact")
	check(gs.bag_fill == 0.0 and gs.compost == 6, "interact empties bag into compost (60 units -> 6)")
	check(player.interaction_target == null, "no target once bag is empty")
	check(not bin.get("_arrow").visible, "arrow hidden after emptying")

	# 4. Находка: скашиваем траву над монетками.
	var coins_find = current_scene.get_node("FindCoins")
	check(field.get_height_at(coins_find.global_position) == 1.0, "tall grass hides the find")
	field.mow(coins_find.global_position, Vector3.FORWARD, 1.0, 1.0)
	for i in 200:
		await process_frame
	check(coins_find.is_collected(), "find collected after grass is cut")
	check(gs.coins == 10, "coin find gives 10 coins")
	check(toasts.any(func(t): return t.begins_with("Найдено: старые монетки")), "find toast")

	# 5. Ёжик: косилка упирается, потом переносим.
	var hedgehog = current_scene.get_node("Hedgehog")
	var start_h: Vector3 = hedgehog.global_position
	player.global_position = start_h + Vector3(3.0, 0, 3.0)
	player.rotation = Vector3(0, PI * 0.25, 0)  # лицом к (-1,-1)
	await hold("move_up", 240)
	var gap: float = player.global_position.distance_to(start_h)
	print("near hedgehog: gap=%.2f target=%s" % [gap, player.interaction_target])
	check(gap > 1.2 and gap < 2.2, "mower stops in front of the hedgehog")
	check(field.get_height_at(start_h) > 0.0, "grass under the hedgehog is not cut")
	check(player.interaction_target == hedgehog, "hedgehog becomes interaction target")
	check(toasts.any(func(t): return t.begins_with("Тут кто-то есть")), "hedgehog notice toast")
	player.try_interact()
	for i in 400:
		await process_frame
	var home: Node3D = current_scene.get_node("AnimalCorner")
	check(hedgehog.is_moved() and hedgehog.global_position.distance_to(home.global_position) < 0.1, "hedgehog hops to its corner")
	await hold("move_up", 120)
	check(field.get_height_at(start_h) == 0.0, "can mow where the hedgehog was")

	# 6. Завершение участка.
	var done := [0]
	plot.completed.connect(func(): done[0] += 1)
	var coins_before: int = gs.coins
	gs.empty_bag()
	# Докашиваем почти всё полосами (нижний метр оставляем).
	field.mow(Vector3(0, 0, -1.0), Vector3.FORWARD, 14.0, 10.0)
	await frames(5)
	print("progress after big cut=%.3f" % field.get_progress())
	check(field.get_progress() < 0.95 and done[0] == 0, "not complete below 95 %")
	var hints_visible := 0
	for i in 60:
		await process_frame
	for h in plot.get("_hints"):
		if h.visible:
			hints_visible += 1
	check(hints_visible == 0 if field.get_progress() < 0.9 else hints_visible > 0, "fireflies match progress (visible=%d)" % hints_visible)
	field.mow(Vector3(0, 0, 4.5), Vector3.FORWARD, 14.0, 1.0)
	await frames(5)
	for i in 60:
		await process_frame
	print("progress=%.3f" % field.get_progress())
	hints_visible = 0
	for h in plot.get("_hints"):
		if h.visible:
			hints_visible += 1
	check(field.get_progress() >= 0.9 and hints_visible > 0, "fireflies mark leftovers above 90 %% (visible=%d)" % hints_visible)
	field.mow(Vector3(0, 0, 5.4), Vector3.FORWARD, 14.0, 0.5)
	await frames(5)
	check(done[0] == 1 and plot.is_completed(), "plot completes at 95 %")
	check(gs.coins == coins_before + 50, "completion reward +50 coins")
	field.mow(Vector3.ZERO, Vector3.FORWARD, 20.0, 20.0)
	await frames(5)
	check(field.get_progress() == 1.0, "progress reaches 100 %")
	check(done[0] == 1, "completion fires only once")
	check(toasts.any(func(t): return t.begins_with("Идеально")), "perfect toast")
	for i in 400:
		await process_frame
	check(hud.get_node("%Completion").visible, "completion window shown after the fly-over")
	var stamps: Array = plot.get_stamps()
	print("stamps: ", stamps)
	check(stamps.all(func(st): return st.earned), "all four stamps earned")

	# 7. Пауза.
	await press("pause")
	check(paused and hud.get_node("%PausePanel").visible, "pause action pauses and shows panel")
	paused = false
	hud.get_node("%PausePanel").visible = false

	# 8. Сохранение и загрузка.
	gs.save_game()
	var saved_coins: int = gs.coins
	var saved_compost: int = gs.compost
	gs.clear()
	check(gs.coins == 0 and gs.plots.is_empty(), "state cleared")
	gs.load_game()
	check(gs.coins == saved_coins and gs.compost == saved_compost, "coins and compost restored")
	reload_current_scene()
	await frames(5)
	plot = get_first_node_in_group("plot")
	check(plot.field.get_progress() == 1.0, "mowing progress restored after reload")
	check(plot.is_completed() and gs.coins == saved_coins, "completed plot does not pay twice")
	hedgehog = current_scene.get_node("Hedgehog")
	check(hedgehog.is_moved() and hedgehog.global_position.distance_to(current_scene.get_node("AnimalCorner").global_position) < 0.1, "hedgehog stays in its corner after reload")
	check(current_scene.get_node("FindCoins").is_collected(), "find stays collected after reload")
	check(not current_scene.get_node("HUD").get_node("%Completion").visible, "no completion window on reload")

	gs.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
