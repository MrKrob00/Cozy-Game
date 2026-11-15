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

	# Своё расписание у каждого участка: во дворе на 1:30 — клевер.
	check(events.SCHEDULE["yard"] == ["clover", "rain", "balloon"] and events.SCHEDULE["garden"] == ["cat", "bees", "rabbit"]
			and events.SCHEDULE["square"] == ["letter", "pigeons", "rainbow"]
			and events.SCHEDULE["orchard"] == ["frogs", "bench", "apples"], "every plot has its own three events")
	check(events.ambient_kinds() == ["birds", "wind"], "at first only birds and wind happen at random")
	events.plot_time["yard"] = 89.5
	await frames(40)
	check(gs.has_flag("event_yard_0") and first("event_clover") != null, "at 1:30 in the yard a four-leaf clover grows")
	first("event_clover").queue_free()
	gs.set_flag("event_yard_1")
	gs.set_flag("event_square_0")
	check("rain" in events.ambient_kinds() and "letter" in events.ambient_kinds() and not "cat" in events.ambient_kinds(),
			"the rain and the postman become random once they have happened on their plots")

	# Почтальон роняет письмо в траву; скосил — нашёл, подъехал — забрал.
	check(events.fire("letter") and village.find_child("PostmanRun", true, false) != null, "the postman runs by")
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
	check(first("event_clover") == null, "a timed event happens once per plot")

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

	# Сад: пчёлы кружат над клумбами.
	var garden = village.get_node("Garden")
	check(events.fire("bees") and village.find_child("Bees", true, false) != null
			and village.find_child("Bees", true, false).get("_bees").size() >= 2, "bees buzz over the garden's flower beds")
	village.find_child("Bees", true, false).queue_free()

	# Кролик с морковкой в траве: скосил рядом — удирает, морковка остаётся.
	player.global_position = yard.field.global_position + Vector3(0.0, 0.0, 2.0)
	await frames(5)
	check(events.fire("rabbit") and first("event_rabbit") != null, "a rabbit munches a carrot in the grass")
	var rabbit = first("event_rabbit")
	check(yard.field.is_open_lawn(rabbit.global_position) and not rabbit.is_fled(), "it sits in a small nibbled clearing")
	coins = gs.coins
	player.global_position = rabbit.global_position + Vector3(1.9, 0.0, 0.0)
	await frames(3)
	check(rabbit.is_fled(), "the mower coming close sends the rabbit running")
	var carrot = get_nodes_in_group("event_gift").filter(func(g): return g.model_name == "carrot")
	if not carrot.is_empty():
		player.global_position = carrot[0].global_position + Vector3(0.3, 0.0, 0.0)
	var carrots := await wait_for(func() -> bool: return gs.coins == coins + 8, 120)
	check(carrots, "the carrot stays and gives coins")

	# Площадь: голуби садятся и взлетают, когда косилка рядом; радуга над фонтаном.
	check(events.fire("pigeons") and village.find_child("Pigeons", true, false) != null, "pigeons fly in")
	var pigeons = village.find_child("Pigeons", true, false)
	await frames(110)
	var a_pigeon: Node3D = pigeons.get("_birds")[0]["node"]
	player.global_position = a_pigeon.global_position + Vector3(0.5, 0.0, 0.0)
	await frames(5)
	check(pigeons.get("_leaving"), "the pigeons take off when the mower comes close")
	var gone_pigeons := await wait_for(func() -> bool: return village.find_child("Pigeons", true, false) == null, 400)
	check(gone_pigeons, "and fly away")
	check(events.fire("rainbow") and village.find_child("Rainbow", true, false) != null, "a rainbow rises over the fountain")

	# Фруктовый сад: лягушки на берегу, гость идёт к лавочке, яблокопад.
	var orchard = village.get_node("Orchard")
	check(events.fire("frogs"), "frogs come out of the pond")
	var chorus = village.find_child("FrogChorus", true, false)
	await frames(240)
	var pond: Node3D = orchard.get_node("Pond")
	var on_bank: int = chorus.get("_frogs").filter(func(f): return (f["node"] as Node3D).global_position.distance_to(pond.global_position) > 2.7).size()
	check(on_bank == 4, "four frogs sit on the bank and croak (%d)" % on_bank)
	# Подъехал к каждой — она ныряет; спугнули всех — хор кончился.
	for frog in chorus.get("_frogs"):
		player.global_position = (frog["node"] as Node3D).global_position + Vector3(0.6, 0.0, 0.6)
		await frames(50)
	check(chorus.frogs_left() == 0, "each frog is scared into the pond one by one")
	var chorus_over := await wait_for(func() -> bool: return village.find_child("FrogChorus", true, false) == null, 200)
	check(chorus_over, "with all four scared the chorus stops")
	check(events.fire("bench"), "a villager comes to sit on the orchard bench")
	var visitor = village.find_child("Visitor", true, false)
	var bench: Node3D = orchard.get_node("Bench")
	var far: float = visitor.global_position.distance_to(bench.global_position)
	await frames(120)
	check(visitor.global_position.distance_to(bench.global_position) < far - 1.5, "the visitor walks towards the bench")
	var apple_tree: Node3D = orchard.get_node("Tree1")
	player.global_position = apple_tree.global_position + Vector3(2.0, 0.0, 2.0)
	await frames(90)
	check(events.fire("apples"), "an apple tree near the hero drops apples")
	var dropped_apples := await wait_for(func() -> bool:
		return get_nodes_in_group("event_gift").filter(func(g): return g.model_name == "apple").size() >= 3, 400)
	check(dropped_apples, "apples land under the tree")

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
