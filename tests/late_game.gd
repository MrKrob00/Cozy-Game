extends SceneTree
# Проверка поздней игры: цепочка открытия участков, повёрнутый участок,
# бурьян, камни, починка фонтана, бюро находок, сон и отрастание травы, праздник.
#
# Запуск из папки проекта:
#   godot --headless --path . --fixed-fps 60 --script tests/late_game.gd
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


func wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await process_frame


## Идти в мировом направлении: north — −Z, south — +Z.
func walk(direction: String, n: int) -> void:
	var actions := ["move_up", "move_right"] if direction == "north" else ["move_down", "move_left"]
	for action: String in actions:
		Input.action_press(action)
	await frames(n)
	for action: String in actions:
		Input.action_release(action)
	await frames(20)


## Скосить участок целиком, не трогая остальные.
func mow_all(plot) -> void:
	plot.field.mow(plot.field.global_position, Vector3.FORWARD, 60.0, 60.0)
	await frames(5)


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
	var square = village.get_node("Square")
	var orchard = village.get_node("Orchard")
	var player = get_first_node_in_group("player")
	var hud = village.get_node("HUD")
	var toasts: Array[String] = []
	gs.toast_requested.connect(func(t): toasts.append(t))

	# 1. Цепочка открытия: двор → сад → площадь → фруктовый сад.
	check(not square.is_unlocked() and not orchard.is_unlocked(), "square and orchard start locked")
	await mow_all(yard)
	await mow_all(garden)
	check(square.is_unlocked() and not orchard.is_unlocked(), "garden unlocks the square only")
	check(is_zero_approx(square.get_progress()) and is_zero_approx(orchard.get_progress()), "mowing other plots does not touch square or orchard")
	print("square %.0f m2, orchard %.0f m2" % [square.field.get("_mowable_cells") / 64.0, orchard.field.get("_mowable_cells") / 64.0])
	await wait(8.0)
	# Показ калиток камерой проверяет tests/village.gd; здесь открываем сразу.
	garden.reveal()
	square.reveal()
	hud.get_node("%Completion").visible = false

	# 2. Площадь повёрнута калиткой к южной дороге: заходим через калитку.
	gs.empty_bag()
	var past_gate: float = await enter_gate(square, player, 300)
	print("in square: ", player.global_position, " past gate ", past_gate, " progress=", square.get_progress())
	check(past_gate > 2.5, "player walks into the rotated plot")
	check(village.current_plot == square, "square becomes the current plot")
	check(square.get_progress() > 0.003 and gs.bag_fill > 1.0, "mowing works on a rotated plot")
	var behind: Vector3 = player.global_position - Vector3(0, 0, 2.0)
	check(square.field.get_height_at(behind) == 0.0, "grass is cut where the mower passed on a rotated plot")

	# 3. Бурьян: слабый нож его не режет, но косилка продирается сквозь него;
	# нож второго уровня режет.
	var weeds: Vector3 = square.get_node("WeedsRight").global_position
	check(square.field.get_height_at(weeds) > 0.95, "weed patch is in place on the rotated plot")
	player.global_position = weeds + Vector3(0, 0, 4.4)
	player.rotation = Vector3(0, 0, 0)
	gs.empty_bag()
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(150)
	var in_weeds_speed: float = player.velocity.length()
	await frames(90)
	Input.action_release("move_up")
	Input.action_release("move_right")
	await frames(20)
	print("at weeds: gap=", player.global_position.distance_to(weeds), " speed in weeds=", in_weeds_speed)
	check(square.field.get_height_at(weeds) > 0.95, "basic blade does not cut weeds")
	check(player.global_position.distance_to(weeds) < 1.6, "the mower can drive through the weeds")
	check(in_weeds_speed > 0.5 and in_weeds_speed < player.speed * 0.6, "but slowly")
	check(toasts.any(func(t): return t.begins_with("Бурьян этот нож не берёт")), "weeds explain what is needed")
	gs.add_coins(60)
	check(gs.buy_upgrade("blade") and player.can_cut_weeds(), "second blade level cuts weeds")
	player.global_position = weeds + Vector3(0, 0, 4.4)
	player.rotation = Vector3(0, 0, 0)
	var bag_before: float = gs.bag_fill
	await walk("north", 300)
	check(square.field.get_height_at(weeds) == 0.0, "weeds are cut with the better blade")
	check(gs.bag_fill > bag_before + 3.0, "weeds fill the bag fast")

	# 4. Камень: мешает, убирается кнопкой, даёт монеты.
	var stone = square.get_node("Stone2")
	player.global_position = stone.global_position + Vector3(0, 0, 1.6)
	player.rotation = Vector3(0, 0, 0)
	await frames(3)
	check(player.interaction_target == stone, "stone becomes interaction target")
	var coins: int = gs.coins
	player.try_interact()
	await wait(0.6)
	check(stone.is_removed() and gs.coins == coins + 2, "removing a stone pays 2 coins")
	check(not stone.can_interact(player), "removed stone is gone")

	# 5. Площадь выкошена: фонтан чинится за монеты, приходит почтальон.
	var repair = square.get_node("FountainRepair")
	check(not repair.can_interact(player), "fountain cannot be repaired before the square is mowed")
	await mow_all(square)
	check(square.is_completed() and orchard.is_unlocked(), "square completes and unlocks the orchard")
	check(repair.can_interact(player), "fountain can be repaired after mowing")
	coins = gs.coins
	repair.interact(player)
	check(repair.is_repaired() and gs.coins == coins - 80, "fountain repair costs 80 coins")
	check(square.get_node("Fountain").get("_fountain_fixed").visible, "repaired fountain shows water")
	await wait(8.0)
	orchard.reveal()
	hud.get_node("%Completion").visible = false
	check(square.get_node("Postman").is_present(), "postman returns after the square is mowed")

	# 6. Бюро находок: вещи с владельцем возвращаются за монеты.
	var glasses = garden.get_node("FindGlasses")
	check(glasses.is_collected() and glasses.can_return(), "found glasses can be returned")
	var bureau = square.get_node("Bureau")
	check(bureau.can_interact(player), "bureau is open after the square is mowed")
	bureau.interact(player)
	await frames(2)
	check(paused and hud.get_node("%WorkshopPanel").visible and hud.get_node("%WorkshopTitle").text == "Бюро находок", "bureau window opens")
	var returnable := get_nodes_in_group("find").filter(func(f): return f.can_return()).size()
	print("returnable finds: ", returnable)
	check(returnable == 5 and hud.get_node("%WorkshopRows").get_child_count() == 5, "bureau lists five owned finds")
	coins = gs.coins
	glasses.give_back()
	check(glasses.is_returned() and not glasses.can_return() and gs.coins == coins + 25, "returning glasses pays 25 coins")
	hud.close_workshop()

	# 7. Сон: новый день, трава на выкошенных участках отрастает, повторный покос даёт монеты.
	var bedtime = yard.get_node("Bedtime")
	check(bedtime.can_interact(player), "player can sleep once the yard is mowed")
	check(gs.day == 1 and is_equal_approx(yard.get_progress(), 1.0), "day 1, yard fully mowed")
	bedtime.interact(player)
	await wait(4.0)
	check(gs.day == 2 and not paused, "night passes and the game resumes on day 2")
	print("after night: yard=%.2f orchard=%.2f" % [yard.get_progress(), orchard.get_progress()])
	check(yard.get_progress() < 0.2 and yard.is_completed(), "grass regrows on a mowed plot, plot stays completed")
	var lawn: Vector3 = yard.global_position + Vector3(2.0, 0, 2.0)
	check(is_equal_approx(yard.field.get_height_at(lawn), 77.0 / 255.0), "regrown grass is short")
	check(is_zero_approx(orchard.get_progress()), "unmowed plot does not change overnight")
	check(yard.get_mood() > 0.79, "regrown plot keeps its bright mood")
	check(yard.get_stamps()[1].earned, "perfect stamp survives regrowth")
	coins = gs.coins
	await mow_all(yard)
	check(gs.coins == coins + 10, "re-mowing the yard pays a small thanks (10 coins)")
	check(toasts.any(func(t): return t.begins_with("Двор снова ухожен")), "re-mow toast")
	await mow_all(yard)
	check(gs.coins == coins + 10, "thanks is paid once per day")

	# 8. Фруктовый сад: лягушки, финал.
	check(orchard.members("animal").size() == 3 and orchard.members("stone").size() == 4, "orchard has frogs and stones")
	var frog = orchard.get_node("Frog1")
	frog.interact(player)
	await wait(4.0)
	check(frog.is_moved() and frog.global_position.distance_to(orchard.get_node("Lily1").global_position) < 0.1, "frog hops to the pond")
	check(not village.is_festival(), "no festival before the last plot")
	await mow_all(orchard)
	check(orchard.is_completed(), "orchard completes")
	await wait(16.0)
	check(village.is_festival(), "festival starts when every plot is mowed")
	check(hud.get_node("%Completion").visible and hud.get_node("%CompletionTitle").text == "Деревня ожила!", "final window is shown")
	check(village.get_node("Decor").get("_bunting") != null, "street gets festival bunting")
	print("summary: ", village.get_summary())
	check(village.get_summary().size() == 4, "summary has four lines")

	# 9. Сохранение: день, возвраты, починка и праздник переживают перезагрузку.
	gs.save_game()
	gs.clear()
	gs.load_game()
	reload_current_scene()
	await frames(5)
	village = current_scene
	check(gs.day == 2, "day restored")
	check(village.get_node("Garden/FindGlasses").is_returned(), "returned find restored")
	check(village.get_node("Square/FountainRepair").is_repaired() and village.get_node("Square/Fountain").get("_fountain_fixed").visible, "repaired fountain restored")
	check(village.get_node("Square/Stone2").is_removed(), "removed stone restored")
	check(village.is_festival() and village.get_node("Decor").get("_bunting") != null, "festival restored with bunting")
	check(not village.get_node("HUD").get_node("%Completion").visible, "final window is not shown again")
	check(village.get_node("Orchard/Frog1").is_moved(), "frog stays in the pond")

	gs.clear()
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
