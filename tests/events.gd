extends SceneTree
# Проверка событий (PlotEvents): по времени на участке — письмо почтальона
# (1:30), грибной дождик (3:00), воздушный шар с посылкой (5:00), каждое
# один раз; случайные — клевер, кот за бабочкой, птицы, ветер.
#
# Запуск из папки проекта:
#   godot --headless --path . --fixed-fps 60 --script tests/events.gd
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
		await process_frame


func wait_for(condition: Callable, limit: int) -> bool:
	for i in limit:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func first(group: String) -> Node:
	var nodes := get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	gs = root.get_node("GameState")
	gs.clear()
	gs.language = "ru"
	gs.apply_language()
	change_scene_to_file("res://scenes/village.tscn")
	await frames(30)
	var village := current_scene
	var events = village.get_node("PlotEvents")
	var yard = village.get_node("Yard")
	var player = get_first_node_in_group("player")
	player.global_position = yard.field.global_position + Vector3(0.0, 0.0, 2.0)
	await frames(10)
	check(events != null and village.current_plot == yard, "the village runs plot events; the yard is current")

	# 1:30 — почтальон роняет письмо в траву; скосил — нашёл, подъехал — забрал.
	events.plot_time["yard"] = 89.5
	await frames(40)
	check(gs.has_flag("event_yard_0") and village.find_child("PostmanRun", true, false) != null,
			"at 1:30 on a plot the postman runs by")
	var dropped := await wait_for(func() -> bool: return first("event_gift") != null, 600)
	var letter = first("event_gift")
	check(dropped and letter.model_name == "letter", "the postman drops a letter onto the plot")
	if letter.is_hidden():
		yard.field.mow(letter.global_position, Vector3.FORWARD, 1.5, 1.5)
		await frames(2)
	check(not letter.is_hidden(), "mowing over the letter uncovers it")
	var coins: int = gs.coins
	player.global_position = letter.global_position + Vector3(0.4, 0.0, 0.0)
	await frames(30)
	check(gs.coins == coins + events.LETTER_COINS and first("event_gift") == null, "driving to the letter collects its coins")
	await wait_for(func() -> bool: return village.find_child("PostmanRun", true, false) == null, 600)
	events.plot_time["yard"] = 0.0
	await frames(5)
	events.plot_time["yard"] = 95.0
	await frames(5)
	check(village.find_child("PostmanRun", true, false) == null, "a timed event happens once per plot")

	# 3:00 — дождик: трава мокнет, минуту после ещё мокрая, потом сохнет.
	check(events.fire("rain") and events.raining, "a sun shower starts")
	await frames(300)
	check(events.wetness == 1.0, "the grass gets wet in the rain")
	gs.bag_fill = 20.0
	var gained: int = gs.empty_bag()
	check(gained == 2, "the rain gives no extra compost (%d)" % gained)
	events.set("_rain_left", 0.01)
	await frames(5)
	check(not events.raining and events.wetness == 1.0, "the rain stops, the grass stays wet with dew")
	events.set("_dry_left", 0.5)
	await frames(40)
	check(events.wetness == 0.0, "and dries in the end")

	# 5:00 — шар сбрасывает посылку.
	check(events.fire("balloon") and village.find_child("Balloon", true, false) != null, "a hot air balloon flies over")
	var landed := await wait_for(func() -> bool: return first("event_gift") != null, 900)
	var parcel = first("event_gift")
	check(landed and parcel.model_name == "parcel", "the balloon drops a parcel on the plot")
	coins = gs.coins
	player.global_position = parcel.global_position + Vector3(0.3, 0.0, 0.0)
	await frames(30)
	check(gs.coins == coins + events.PARCEL_COINS, "the parcel gives its coins")

	# Клевер: появляется в нескошенной траве; скосил — монеты.
	player.global_position = yard.field.global_position + Vector3(0.0, 0.0, 2.0)
	check(events.fire("clover") and first("event_clover") != null, "a four-leaf clover grows in uncut grass")
	var clover = first("event_clover")
	check(yard.field.get_height_at(clover.global_position) > 0.0, "the clover stands in uncut grass")
	coins = gs.coins
	yard.field.mow(clover.global_position, Vector3.FORWARD, 1.0, 1.0)
	await frames(5)
	check(gs.coins == coins + events.CLOVER_COINS and first("event_clover") == null, "mowing the clover gives coins")
	events.fire("clover")
	clover = first("event_clover")
	coins = gs.coins
	clover.life = 0.1
	await frames(70)
	check(first("event_clover") == null and gs.coins == coins, "an unmowed clover wilts without a reward")

	# Кот за бабочкой: косилка рядом — кот пугается и убегает.
	check(events.fire("cat"), "a cat chases a butterfly")
	var chase = village.find_child("CatChase", true, false)
	await frames(10)
	var cat: Node3D = chase.get_node("Cat")
	player.global_position = cat.global_position + Vector3(0.5, 0.0, 0.0)
	await frames(5)
	check(chase.is_scared(), "the mower scares the cat")
	await frames(240)
	check(not is_instance_valid(chase), "the scared cat runs off and is gone")
	player.global_position = yard.field.global_position + Vector3(0.0, 0.0, 2.0)
	events.fire("cat")
	var gone := await wait_for(func() -> bool: return village.find_child("CatChase", true, false) == null, 900)
	check(gone, "a cat left alone follows the butterfly away")

	# Ёжик в своём уголке: косилка едет на него — он отбегает в сторону.
	var hedgehog = null
	for animal in get_nodes_in_group("animal"):
		if animal.kind == 0:
			hedgehog = animal
	gs.set_flag("animal_" + hedgehog.animal_id)
	hedgehog.call("_settle_at_home")
	hedgehog.set("_moved", true)
	var sat: Vector3 = hedgehog.global_position
	player.global_position = sat + Vector3(1.0, 0.0, 0.0)
	await frames(90)
	var moved_by := Vector2(hedgehog.global_position.x - sat.x, hedgehog.global_position.z - sat.z).length()
	check(moved_by > 1.5 and hedgehog.global_position.distance_to(player.global_position) > 1.8,
			"the hedgehog in its corner scurries away from the mower (%.1f m)" % moved_by)
	check(yard.field.contains(hedgehog.global_position), "and stays on its plot")

	# Птицы и ветер: пролетают и исчезают.
	check(events.fire("birds") and village.find_child("Birds", true, false) != null, "a flock of birds flies over")
	check(events.fire("wind") and village.find_child("Gust", true, false) != null, "a gust blows leaves across")
	var flew := await wait_for(func() -> bool:
		return village.find_child("Birds", true, false) == null and village.find_child("Gust", true, false) == null, 600)
	check(flew, "the birds and the leaves are gone afterwards")

	gs.clear()
	if FileAccess.file_exists("user://save.dat"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.dat"))
	print("RESULT: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
