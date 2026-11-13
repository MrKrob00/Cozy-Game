extends SceneTree
# Проверка деревни: закрытая калитка, апгрейды и мастерская, открытие сада
# после двора, жители, полевые цветы, сохранение апгрейдов.
#
# Запуск из папки проекта:
#   godot --headless --path . --fixed-fps 60 --script tests/village.gd
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


## Идти в мировом направлении −Z (на экране это «вверх и вправо»).
func walk_north(n: int) -> void:
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(n)
	Input.action_release("move_up")
	Input.action_release("move_right")
	await frames(20)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	gs = root.get_node("GameState")
	gs.clear()
	change_scene_to_file("res://scenes/village.tscn")
	await frames(5)
	var village = current_scene
	var yard = village.get_node("Yard")
	var garden = village.get_node("Garden")
	var player = get_first_node_in_group("player")
	var hud = village.get_node("HUD")
	var toasts: Array[String] = []
	gs.toast_requested.connect(func(t): toasts.append(t))

	# 0. Титульный экран: без экрана его нет; показанный — игрок ждёт, «Играть» отпускает.
	check(not hud.is_title_shown() and player.controls_enabled, "no title screen in headless runs")
	hud.call("_show_title")
	check(hud.is_title_shown() and not player.controls_enabled, "title screen holds the player")
	check(hud.get_node("%PlayButton").text == "Играть" and not hud.get_node("%NewGameButton").visible, "fresh game offers Play only")
	var start_pos: Vector3 = player.global_position
	Input.action_press("move_up")
	await frames(30)
	Input.action_release("move_up")
	check(player.global_position.distance_to(start_pos) < 0.01, "player does not move behind the title")
	hud.get_node("%PlayButton").pressed.emit()
	await frames(40)
	check(not hud.is_title_shown() and player.controls_enabled and gs.title_seen, "Play hands control to the player")

	# 1. Два участка; игрок начинает во дворе.
	check(get_nodes_in_group("plot").size() == 4, "village has four plots")
	check(village.current_plot == yard, "player starts in the yard")
	check(hud.get_node("%ProgressLabel").text.begins_with("Двор"), "HUD shows the yard")
	check(yard.is_unlocked() and not garden.is_unlocked(), "garden is locked until the yard is mowed")
	check(yard.get_walk_rects().size() == 2 and garden.get_walk_rects().size() == 1, "locked plot has no gate passage")
	var yard_cells: int = yard.field.get("_mowable_cells")
	var garden_cells: int = garden.field.get("_mowable_cells")
	print("yard %.0f m2, garden %.0f m2" % [yard_cells / 64.0, garden_cells / 64.0])
	check(garden_cells > yard_cells * 1.3, "garden is bigger than the yard")
	check(yard.members("find").size() == 3 and garden.members("find").size() == 3, "finds belong to their plots")
	check(garden.get_stamps().size() == 6, "garden has six stamps (with wild flowers)")

	# 2. Выход на улицу через калитку двора, закрытая калитка сада не пускает.
	var gate: Vector3 = garden.fence.get_gate_position()
	player.global_position = Vector3(gate.x, 0, 11.0)
	player.rotation = Vector3(0, 0, 0)
	await walk_north(300)
	print("at locked gate: ", player.global_position)
	check(player.global_position.z > 9.3, "locked gate keeps the player on the street")
	check(toasts.any(func(t): return t.begins_with("Сад бабушки пока закрыт")), "locked gate explains itself")
	check(garden.get_progress() == 0.0, "nothing mowed behind the locked gate")

	# 3. Апгрейды.
	check(is_equal_approx(player.blade_width, 0.6) and is_equal_approx(player.speed, 2.5) and gs.bag_capacity == 60.0, "base mower stats")
	check(not gs.buy_upgrade("blade"), "cannot buy without coins")
	gs.add_coins(1000)
	check(gs.buy_upgrade("blade") and gs.coins == 940, "blade upgrade costs 60")
	check(is_equal_approx(player.blade_width, 0.8), "blade is wider after upgrade")
	check(is_equal_approx(player.get_node("MowerShape").shape.size.x, 0.9), "mower collision follows blade width")
	check(gs.buy_upgrade("bag") and gs.bag_capacity == 100.0 and gs.coins == 890, "bag upgrade")
	check(gs.buy_upgrade("motor") and is_equal_approx(player.speed, 3.0) and gs.coins == 830, "motor upgrade")
	check(gs.buy_upgrade("blade") and gs.buy_upgrade("bag") and gs.buy_upgrade("motor"), "second tier upgrades")
	check(is_equal_approx(player.blade_width, 1.0) and gs.bag_capacity == 150.0 and is_equal_approx(player.speed, 3.5), "max mower stats")
	check(gs.coins == 830 - 220 - 200 - 240, "second tier costs")
	check(gs.is_upgrade_maxed("blade") and not gs.buy_upgrade("blade") and gs.upgrade_cost("blade") == -1, "maxed upgrade cannot be bought")

	# 4. Мастерская: закрыта без ключа, открывается с ключом.
	var workshop = yard.get_node("Workshop")
	check(not workshop.can_interact(player), "workshop is closed without the key")
	gs.set_flag("find_shed_key")
	await frames(3)
	check(workshop.can_interact(player), "key opens the workshop")
	check(not yard.get_node("Shed").get("_padlock").visible, "padlock is gone")
	workshop.interact(player)
	await frames(2)
	check(paused and hud.get_node("%WorkshopPanel").visible, "workshop window opens and pauses the game")
	check(hud.get_node("%WorkshopRows").get_child_count() >= 3, "workshop lists upgrades")
	hud.close_workshop()
	check(not paused and not hud.get_node("%WorkshopPanel").visible, "workshop window closes")

	# 5. Двор выкошен — сад открывается, возвращается Мастер.
	var master = yard.get_node("Master")
	check(not master.is_present() and not master.visible, "master is away at first")
	yard.field.mow(yard.global_position, Vector3.FORWARD, 30.0, 30.0)
	await frames(5)
	check(yard.is_completed() and garden.is_unlocked(), "mowing the yard unlocks the garden")
	check(garden.get_walk_rects().size() == 2, "garden gate passage appears")
	check(toasts.any(func(t): return t.begins_with("Калитка в сад бабушки открыта")), "unlock toast")
	check(garden.fence.has_guide_arrow(), "an arrow over the garden gate shows the way")
	check(garden.get_progress() == 0.0, "mowing the yard does not touch the garden")
	for i in 460:
		await process_frame
	check(master.is_present() and master.visible, "master returns after the yard is mowed")
	hud.get_node("%Completion").visible = false

	# 6. Заходим в сад через калитку и косим.
	player.global_position = Vector3(gate.x, 0, 11.0)
	player.rotation = Vector3(0, 0, 0)
	gs.empty_bag()
	await walk_north(260)
	print("in garden: ", player.global_position, " progress=", garden.get_progress(), " bag=", gs.bag_fill)
	check(player.global_position.z < 6.0, "player walks through the open gate")
	check(village.current_plot == garden, "garden becomes the current plot")
	check(hud.get_node("%ProgressLabel").text.begins_with("Сад бабушки"), "HUD switches to the garden")
	check(garden.get_progress() > 0.005 and gs.bag_fill > 2.0, "mowing works on the second plot")
	check(not garden.fence.has_guide_arrow(), "the guide arrow goes once the player mows the garden")

	# 7. Полевые цветы: наехали — скошены, объехали — остались.
	var poppies = garden.get_node("Poppies")
	check(poppies.is_alive(), "wild flowers start alive")
	player.global_position = poppies.global_position + Vector3(0, 0, 3.0)
	player.rotation = Vector3(0, 0, 0)
	await walk_north(120)
	check(not poppies.is_alive(), "driving over wild flowers cuts them")
	check(toasts.any(func(t): return t.begins_with("Полевые цветы!")), "wild flowers hint")
	check(garden.get_node("Daisies").is_alive(), "other wild flowers are untouched")

	# 8. Сад выкошен: награда и бонус за три сохранённые куртины, приходит бабушка.
	var coins_before: int = gs.coins
	garden.field.mow(garden.global_position, Vector3.FORWARD, 40.0, 40.0)
	await frames(5)
	check(garden.is_completed(), "garden completes")
	check(gs.coins == coins_before + 120 + 15, "garden reward plus bonus for 3 saved flower patches")
	var grandma = garden.get_node("Grandma")
	for i in 460:
		await process_frame
	check(grandma.is_present(), "grandma returns to her garden")
	var stamps: Array = garden.get_stamps()
	check(not stamps[5].earned and stamps[5].title.contains("3 из 4"), "wild flowers stamp counts saved patches")

	# 9. Сохранение: апгрейды и срезанные цветы переживают перезагрузку.
	gs.save_game()
	var saved_coins: int = gs.coins
	gs.clear()
	gs.load_game()
	reload_current_scene()
	await frames(5)
	village = current_scene
	player = get_first_node_in_group("player")
	check(gs.coins == saved_coins and gs.upgrade_level("blade") == 2, "coins and upgrades restored")
	check(is_equal_approx(player.blade_width, 1.0) and is_equal_approx(player.speed, 3.5), "player uses restored upgrades")
	check(village.get_node("Garden").is_unlocked() and village.get_node("Garden").is_completed(), "garden state restored")
	check(not village.get_node("Garden/Poppies").is_alive() and village.get_node("Garden/Daisies").is_alive(), "wild flowers state restored")
	check(village.get_node("Yard/Master").is_present() and village.get_node("Garden/Grandma").is_present(), "villagers stay after reload")
	check(village.get_node("Yard/Workshop").can_interact(player), "workshop stays open after reload")

	gs.clear()
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
