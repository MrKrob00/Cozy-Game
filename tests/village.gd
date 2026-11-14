extends SceneTree
# Проверка деревни: закрытая калитка, апгрейды и мастерская, открытие сада
# после двора (показ калитки и дорожка стрелок), жители, сохранение апгрейдов.
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


## Ставит игрока на дороге перед калиткой участка лицом к ней и ведёт внутрь
## n кадров. Возвращает, насколько игрок прошёл за калитку, в метрах
## (отрицательное — остался снаружи). Работает при любом повороте участка.
func enter_gate(plot, player, n: int) -> float:
	var gate: Vector3 = plot.fence.get_gate_position()
	var outward: Vector3 = plot.fence.global_basis.z.normalized()
	var inward := -outward
	player.global_position = gate + outward * 2.6
	player.look_at(player.global_position + inward, Vector3.UP)
	# Ввод задаётся относительно камеры: «вправо» — (1, 0, −1), «вверх» — (−1, 0, −1).
	var actions: Array[String] = []
	var right := inward.x - inward.z
	var up := -inward.x - inward.z
	if absf(right) > 0.3:
		actions.append("move_right" if right > 0.0 else "move_left")
	if absf(up) > 0.3:
		actions.append("move_up" if up > 0.0 else "move_down")
	for action in actions:
		Input.action_press(action)
	await frames(n)
	for action in actions:
		Input.action_release(action)
	await frames(20)
	return (player.global_position - gate).dot(inward)


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
	check(garden.global_position.y > yard.global_position.y + 1.0, "each next plot sits higher")
	# Окружение запечено заранее и не строится при запуске.
	var map_bake = load("res://scripts/map_bake.gd")
	check(ResourceLoader.exists(map_bake.BASE) and village.get_node_or_null("Decor/Decor") != null, "the game loads the baked map instead of building it")
	var baked_scene: Node = load(map_bake.BASE).instantiate()
	check(baked_scene.get_meta("bake_key", "") == map_bake.source_key(), "the baked map is up to date (else run tools/bake_map.gd)")
	baked_scene.free()
	for quality in 3:
		check(ResourceLoader.exists(map_bake.SCATTER % quality), "meadow scatter is baked for graphics preset %d" % quality)
	# Карта — «звезда»: поляна в середине, от неё к каждой калитке своя дорога.
	var terrain = village.get_node("Terrain")
	check(terrain.roads.size() == 5 and terrain.roads[0].get("green", false), "the village is a green with a road to each plot")
	var junctions := 0
	for a in terrain.roads:
		for b in terrain.roads:
			if a != b and a["rect"].intersects(b["rect"]):
				var overlap: Rect2 = a["rect"].intersection(b["rect"])
				var center := overlap.get_center()
				junctions += 1
				if absf(terrain.road_height(a, center) - terrain.road_height(b, center)) > 0.02:
					check(false, "roads %s and %s meet at different heights" % [a["name"], b["name"]])
	check(junctions == 8, "every road meets the green and nothing else (%d junction pairs)" % junctions)
	for plot in get_nodes_in_group("plot"):
		var to_green: float = Vector2(plot.fence.get_gate_position().x, plot.fence.get_gate_position().z).distance_to(terrain.GREEN_CENTER)
		check(to_green < 22.0, "%s gate is a short walk from the green (%.0f m)" % [plot.plot_name, to_green])
	for plot in get_nodes_in_group("plot"):
		var gate_at: Vector3 = plot.fence.get_gate_position()
		var outside: Vector3 = gate_at + plot.fence.global_basis.z.normalized() * 1.6
		check(terrain.road_depth(Vector2(outside.x, outside.z)) > 0.0, "%s gate opens onto a road" % plot.plot_name)
		check(absf(terrain.height_at(Vector2(outside.x, outside.z)) - plot.global_position.y) < 0.02, "%s gate is level with its road" % plot.plot_name)
	check(garden.fence.get("_sign_label").text.contains("закрыто"), "a locked plot's signpost says closed")
	check(yard.get_walk_rects().size() == 2 and garden.get_walk_rects().size() == 1, "locked plot has no gate passage")
	var yard_cells: int = yard.field.get("_mowable_cells")
	var garden_cells: int = garden.field.get("_mowable_cells")
	print("yard %.0f m2, garden %.0f m2" % [yard_cells / 64.0, garden_cells / 64.0])
	check(garden_cells > yard_cells * 1.3, "garden is bigger than the yard")
	check(yard.members("find").size() == 3 and garden.members("find").size() == 3, "finds belong to their plots")
	check(garden.get_stamps().size() == 5, "garden has five stamps")

	# 2. Выход на улицу через калитку двора, закрытая калитка сада не пускает.
	var past_gate: float = await enter_gate(garden, player, 300)
	print("at locked gate: ", player.global_position, " past gate ", past_gate)
	check(past_gate < -0.8, "locked gate keeps the player on the road")
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
	player.global_position = Vector3(0, 0, 3.0)
	await frames(3)
	yard.field.mow(yard.global_position, Vector3.FORWARD, 30.0, 30.0)
	await frames(5)
	check(yard.is_completed() and garden.is_unlocked(), "mowing the yard unlocks the garden")
	check(garden.reveal_pending and garden.get_walk_rects().size() == 1, "the gate stays shut until the player is shown it")
	var trail = village.get_node("GuideTrail")
	check(village.next_goal() == null and trail.mark_count() == 0, "no trail before the gate is shown")
	check(garden.get_progress() == 0.0, "mowing the yard does not touch the garden")
	for i in 460:
		await process_frame
	check(master.is_present() and master.visible, "master returns after the yard is mowed")
	# Окно завершения закрыто: камера едет к калитке сада, и она открывается.
	var camera = village.get_node("Camera")
	hud.get_node("%Completion").visible = false
	await frames(2)
	check(camera.is_revealing() and not player.controls_enabled, "the camera goes to show the new gate, the player waits")
	await frames(110)
	var gate_at: Vector3 = garden.fence.get_gate_position()
	check(not garden.reveal_pending and garden.get_walk_rects().size() == 2, "garden gate passage appears")
	check(camera.global_position.distance_to(gate_at) < camera.global_position.distance_to(player.global_position), "the camera is at the garden gate while it opens")
	check(toasts.any(func(t): return t.begins_with("Калитка в сад бабушки открыта")), "unlock toast")
	check(garden.fence.has_guide_arrow(), "an arrow over the garden gate shows the way")
	check(garden.fence.get("_sign_label").text.contains("Сад бабушки") and not garden.fence.get("_sign_label").text.contains("закрыто"), "the garden signpost no longer says closed")
	await frames(220)
	check(not camera.is_revealing() and player.controls_enabled, "the camera comes back and the player moves again")
	var pointer = hud.get_node("Root/GoalPointer")
	check(pointer.target == garden and village.next_goal() == garden, "the screen-edge pointer leads to the garden")
	check(pointer.visible and pointer.size.x > 100.0, "the pointer is drawn at the screen edge while the gate is out of view")
	# Дорожка стрелок на земле: от игрока до калитки, только по проходимым местам.
	var path: PackedVector2Array = trail.get_path_to_goal()
	check(trail.mark_count() > 8, "arrows on the ground lead to the garden (%d)" % trail.mark_count())
	check(path.size() >= 3 and path[-1].distance_to(Vector2(gate_at.x, gate_at.z)) < 0.1, "the trail ends at the garden gate")
	var walkable := true
	for i in path.size() - 1:
		for k in 11:
			var point: Vector2 = path[i].lerp(path[i + 1], k / 10.0)
			var inside := false
			for area in get_nodes_in_group("walk_area"):
				for rect: Rect2 in area.get_walk_rects():
					if rect.grow(0.45).has_point(point):
						inside = true
			if not inside or point.distance_to(terrain.GREEN_CENTER) < 1.2:
				walkable = false
	check(walkable, "the trail stays where the player can walk and goes round the well")
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	check(length < 45.0, "the way to the next plot is short (%.0f m)" % length)

	# 6. Заходим в сад через калитку и косим.
	gs.empty_bag()
	past_gate = await enter_gate(garden, player, 260)
	print("in garden: ", player.global_position, " past gate ", past_gate, " progress=", garden.get_progress(), " bag=", gs.bag_fill)
	check(past_gate > 2.5, "player walks through the open gate")
	check(absf(player.global_position.y - garden.global_position.y) < 0.05, "player stands on the garden terrace")
	check(village.current_plot == garden, "garden becomes the current plot")
	check(hud.get_node("%ProgressLabel").text.begins_with("Сад бабушки"), "HUD switches to the garden")
	check(garden.get_progress() > 0.005 and gs.bag_fill > 2.0, "mowing works on the second plot")
	check(not garden.fence.has_guide_arrow(), "the guide arrow goes once the player mows the garden")

	check(trail.mark_count() == 0 and village.next_goal() == null, "the trail goes once the player mows the garden")

	# 7. Сад выкошен: награда, приходит бабушка.
	var coins_before: int = gs.coins
	garden.field.mow(garden.global_position, Vector3.FORWARD, 40.0, 40.0)
	await frames(5)
	check(garden.is_completed(), "garden completes")
	check(gs.coins == coins_before + 120, "garden reward")
	var grandma = garden.get_node("Grandma")
	for i in 460:
		await process_frame
	check(grandma.is_present(), "grandma returns to her garden")

	# 8. Сохранение: апгрейды переживают перезагрузку.
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
	check(not village.get_node("Garden").reveal_pending and village.get_node("Garden").get_walk_rects().size() == 2, "an unlocked gate is open after reload")
	check(village.get_node("Yard/Master").is_present() and village.get_node("Garden/Grandma").is_present(), "villagers stay after reload")
	check(village.get_node("Yard/Workshop").can_interact(player), "workshop stays open after reload")

	gs.clear()
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
