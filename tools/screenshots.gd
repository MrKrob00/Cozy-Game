extends "res://tools/trailer.gd"
## Снимки для страницы игры на itch.io: обложка, баннер, семь скриншотов и
## картинка для соцсетей. Размеры — по шаблонам hedgiespresso
## (https://hedgiespresso.itch.io/itch-page-image-templates):
##   обложка — 630×500 (снимаем вдвое крупнее, 1260×1000: те же пропорции);
##   баннер — 960 в ширину, не выше 400 (300); он заменяет название, поэтому
##     название на нём;
##   скриншоты — 1920×1080; в колонке страницы они ужимаются до 347 в ширину,
##     поэтому подписи крупные, а по щелчку открываются целиком;
##   картинка для соцсетей — 1200×630, главное — в квадрате 620×620 в центре;
##   каждый файл — меньше 3 МБ.
##
## Сюжет скриншотов — путь игры, по порядку, как в трейлере:
##   1. заросший двор и первая полоса (ёжик на пути);
##   2. полосатый газон — вид как в игре;
##   3. находка выпрыгивает из травы;
##   4. мастерская: улучшения косилки;
##   5. площадь в бурьяне — новая косилка;
##   6. фруктовый сад: лягушки у пруда;
##   7. праздник: деревня ожила.
##
## Запуск (нужен экран или xvfb):
##   xvfb-run -a -s "-screen 0 2560x1600x24" godot --path . \
##       --rendering-driver opengl3 --fixed-fps 30 --script tools/screenshots.gd
## Снимки ложатся в docs/itch/.

const OUT := "res://docs/itch"
const SHOT_SIZE := Vector2i(1920, 1080)
const COVER_SIZE := Vector2i(1260, 1000)
const BANNER_RENDER := Vector2i(1920, 600)
const BANNER_SIZE := Vector2i(960, 300)
const SOCIAL_SIZE := Vector2i(1200, 630)
## Подписи скриншотов: в колонке страницы снимок в 5,5 раз меньше.
const CAPTION_FONT := 84

var _title_box: Control


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_state = root.get_node("GameState")
	_sfx = root.get_node("Sfx")
	Engine.set_meta("baking_map", true)
	_state.clear()
	_state.title_seen = true
	_state.graphics_quality = 2
	_state.language = "en"
	_state.apply_language()
	_state.music_enabled = false
	_state.settings_changed.emit()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
	await _resize(SHOT_SIZE)
	change_scene_to_file("res://scenes/village.tscn")
	await frames(12)
	_village = current_scene
	_player = get_first_node_in_group("player")
	_camera = _village.get_node("Camera")
	_hud = _village.get_node("HUD")
	for button: String in ["%PauseButton", "%CameraButton"]:
		for child in _hud.get_node(button).get_children():
			if child is Label:
				child.visible = false
	_terrain = _village.get_node("Terrain")
	_placeholder = load("res://scripts/placeholder.gd")
	_juice = load("res://scripts/juice.gd")
	_fields = get_nodes_in_group("mow_field")
	_hud.get_node("%HintLabel").visible = false
	_hud.get_node("%Completion").modulate.a = 0.0
	_hud.get_node("%Completion").mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.get_node("%Toast").self_modulate.a = 0.0
	_hud.get_node("%ToastLabel").self_modulate.a = 0.0
	_hud.get_node("%ActionButton").self_modulate.a = 0.0
	_hud.get_node("%ActionButton").add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_player.set_physics_process(false)
	_hud.auto_reveal = false
	_build_overlay()
	_caption_label.add_theme_font_size_override("font_size", CAPTION_FONT)
	var yard: Node3D = _village.get_node("Yard")
	var garden: Node3D = _village.get_node("Garden")
	var square: Node3D = _village.get_node("Square")
	var orchard: Node3D = _village.get_node("Orchard")
	var events: Node = _village.get_node("PlotEvents")
	var hedgehog: Node3D = yard.get_node("Hedgehog")
	hedgehog.set("_noticed", true)
	yard.complete_at = 1.01

	# --- 1. Заросший двор: две полосы скошены, герой идёт третьей, на
	# пути в высокой траве — ёжик. Обложка снимается тут же.
	_set_route(_serpentine(yard, [2.1, 2.85], 5.6, -5.6))
	while _advance(40.0, yard):
		pass
	var hog := hedgehog.global_position
	_set_route(PackedVector2Array([_local(yard, hedgehog.position.x, 5.6),
			_local(yard, hedgehog.position.x, hedgehog.position.z + 2.3)]))
	_teleport()
	_set_hud(false)
	_camera.set_process(false)
	var hook_from := hog + Vector3(2.5, 1.25, -1.9)
	var hook_look := hog + Vector3(-0.15, 0.5, 1.4)
	_place_camera(hook_from, hook_look)
	await _walk(yard, 2.0, 3.2)
	await frames(6)
	await _shot("1_overgrown_yard", "Turn the overgrown into a cozy garden")
	await _resize(COVER_SIZE)
	_place_camera(hog + Vector3(3.2, 2.7, -3.9), hog + Vector3(-0.3, 1.15, 1.0))
	_show_title_box(Vector2(0.5, 0.0), 170, true)
	await _capture("cover", COVER_SIZE)
	await _resize(SOCIAL_SIZE)
	_place_camera(hog + Vector3(3.2, 2.4, -3.7), hog + Vector3(-0.3, 1.05, 1.0))
	_show_title_box(Vector2(0.5, 0.0), 120, false)
	await _capture("social", SOCIAL_SIZE)
	_hide_title_box()
	await _resize(SHOT_SIZE)

	# --- 2. Полосатый газон, вид как в игре: двор скошен полосами, кроме
	# последних, по которым идёт герой.
	_set_route(_serpentine(yard, [hedgehog.position.x, 4.35, 5.1, 5.85], hedgehog.position.z + 2.2, -5.6))
	_premow_except_route(yard)
	_hud.get_node("%Margin").visible = true
	_set_hud(true)
	_follow_camera(1)
	_route_at = _route_length * 0.35
	_teleport_at()
	await _walk(yard, 2.4, 1.5)
	await _shot("2_stripes", "Mow it stripe by stripe")

	# --- 3. Сад бабушки: очки выпрыгивают из травы.
	_complete_silently(yard)
	garden.reveal()
	await frames(4)
	var glasses: Node3D = garden.get_node("FindGlasses")
	_set_route(PackedVector2Array([_local(garden, glasses.position.x, glasses.position.z + 3.2),
			_local(garden, glasses.position.x, glasses.position.z - 1.0)]))
	_teleport()
	_set_hud(false)
	_camera.set_process(false)
	# Сбоку: очки взлетают перед косилкой и не заслоняют героя.
	var side: Vector3 = garden.to_global(Vector3(glasses.position.x + 4.3, 0.0, glasses.position.z - 0.4))
	# Низко: тёмные очки взлетают на фоне неба.
	_place_camera(side + Vector3.UP * 0.8, garden.to_global(Vector3(glasses.position.x, 1.35, glasses.position.z + 0.55)))
	var popped := false
	for i in 150:
		_advance(1.9, garden)
		await process_frame
		if glasses.get("_revealed"):
			popped = true
			break
	_player.set("_current_speed", 0.0)
	await frames(13)
	if not popped:
		push_warning("the glasses did not pop out")
	await _shot("3_find", "Find what the neighbours lost")

	# --- 4. Мастерская: окно улучшений над двором.
	_complete_silently(garden)
	_state.coins = 186
	_state.coins_changed.emit(_state.coins)
	_state.upgrade_levels = {"blade": 1, "bag": 1, "motor": 0}
	_state.upgrades_changed.emit()
	_set_route(PackedVector2Array([_local(yard, 5.2, -4.6), _local(yard, 5.2, -5.6)]))
	_teleport()
	_advance(0.01, null)
	_set_hud(true)
	_follow_camera(1)
	await frames(30)
	_hud.open_workshop()
	await frames(20)
	await _shot("4_workshop", "Upgrade your mower")
	_hud.close_workshop()

	# --- 5. Площадь: улучшенная косилка идёт сквозь бурьян.
	_state.upgrade_levels = {"blade": 2, "bag": 1, "motor": 2}
	_state.upgrades_changed.emit()
	square.fence.set_gate_open(true, false)
	square.fence.call("_update_sign", square)
	_premow(square, 0.49)
	_set_hud(false)
	_set_route(PackedVector2Array([_local(square, -0.54, -5.6), _local(square, 10.4, -5.6)]))
	_teleport()
	_advance(0.01, square)
	_camera.set_process(false)
	for i in 70:
		_advance(WALK_PACE, square)
		_chase_camera(Vector3(-3.1, 2.3, -4.8), Vector3(0.0, 0.8, -1.2))
		await process_frame
	await _shot("5_weeds", "Tame the weeds")

	# --- 6. Фруктовый сад: лягушки вылезли из пруда и квакают.
	_complete_silently(square)
	orchard.fence.set_gate_open(true, false)
	orchard.fence.call("_update_sign", orchard)
	_premow(orchard, 0.43)
	# Камера со стороны середины сада, сверху: пруд, лягушки и герой,
	# который косит рядом.
	var pond: Vector3 = orchard.get_node("Pond").global_position
	var inward: Vector3 = orchard.global_position - pond
	inward.y = 0.0
	inward = inward.normalized()
	var across := inward.cross(Vector3.UP)
	var lane := pond + inward * 4.4
	_set_route(PackedVector2Array([Vector2(lane.x - across.x * 3.0, lane.z - across.z * 3.0),
			Vector2(lane.x + across.x * 1.5, lane.z + across.z * 1.5)]))
	_teleport()
	_advance(0.01, orchard)
	events.fire("frogs")
	_camera.set_process(false)
	# С дальнего берега, низко: лягушки на ближнем берегу, за прудом —
	# герой и деревья сада.
	_place_camera(pond - inward * 5.6 + across * 1.2 + Vector3.UP * 1.9, pond + inward * 2.2 + Vector3.UP * 0.3)
	for i in 80:
		if i < 50:
			_advance(1.4, orchard)
		else:
			_player.set("_current_speed", 0.0)
		await process_frame
	await _shot("6_orchard", "Little surprises in every garden")

	# --- 7. Праздник: все участки выкошены, конфетти.
	_complete_silently(orchard)
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
	_camera.set("_distance_offset", -2.0)
	_camera.set("_yaw_offset", -24.0)
	_camera.pitch_degrees = 34.0
	await frames(40)
	# Камера праздника медленно кружит: снимаем с того места, где она сейчас.
	_camera.set_process(false)
	await frames(60)
	await _volley(3)
	await _shot("7_festival", "Bring the whole village back to life")

	# --- Баннер: праздник с высоты, название посередине.
	await _resize(BANNER_RENDER)
	_camera.set("_distance_offset", 4.0)
	_camera.pitch_degrees = 26.0
	_camera.set_process(true)
	await frames(2)
	_camera.set_process(false)
	await frames(30)
	await _volley(2)
	_show_title_box(Vector2(0.5, 0.5), 190, false)
	await _capture("banner", BANNER_SIZE)
	_hide_title_box()

	_state.clear()
	_state.graphics_quality = -1
	_state.language = ""
	quit()


# --- Снимки ---

# Скриншот 1920×1080 с подписью внизу.
func _shot(file: String, caption: String) -> void:
	_say(caption)
	await frames(14)
	_caption.scale = Vector2.ONE
	await _capture(file, SHOT_SIZE)
	_say("")


# Сохраняет кадр (JPG, качество 92) в размере size.
func _capture(file: String, size: Vector2i) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path("%s/%s.jpg" % [OUT, file])
	image.save_jpg(path, 0.92)
	print("SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	# Окно меняется, а область отрисовки — нет: её размер задаётся отдельно.
	root.size = size
	await frames(6)
	if DisplayServer.window_get_size() != size:
		push_warning("window is %s, not %s" % [DisplayServer.window_get_size(), size])


# Герой идёт по маршруту несколько секунд (из травы летит покос).
func _walk(plot: Node3D, speed: float, seconds: float) -> void:
	for i in int(seconds * FPS):
		_advance(speed, plot)
		await process_frame


# Ставит героя в текущую точку маршрута.
func _teleport_at() -> void:
	var along := _route_at
	_advance(0.0, null)
	_route_at = along
	_camera.set("_focus", _player.global_position)


func _place_camera(at: Vector3, look: Vector3) -> void:
	_camera.global_position = at
	_camera.look_at(look, Vector3.UP)


# Залпы конфетти над площадью праздника.
func _volley(count: int) -> void:
	for volley in count:
		for i in 3:
			var at := Vector3(-5.0 + ((volley * 5 + i * 4) % 11), 2.6 + (volley % 2) * 0.6,
					23.0 + ((volley * 3 + i * 2) % 6))
			_juice.confetti(_village, at, 60)
			_juice.sparkle(_village, at, Color(1.0, 0.92, 0.6), 24)
		await frames(8)
	await frames(10)


# --- Название ---

# Название и слоган; anchor — где на экране (0…1), size — кегль названия.
func _show_title_box(anchor: Vector2, size: int, tagline_shown: bool) -> void:
	_hide_title_box()
	var screen := root.get_visible_rect().size
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_overlay.add_child(column)
	var title := Label.new()
	title.text = "Cozy Grass Cut"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", size)
	title.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	title.add_theme_color_override("font_outline_color", Color(0.33, 0.24, 0.12))
	title.add_theme_constant_override("outline_size", int(size * 0.24))
	column.add_child(title)
	if tagline_shown:
		var tagline := Label.new()
		tagline.text = "One cozy stripe at a time"
		tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tagline.add_theme_font_size_override("font_size", int(size * 0.4))
		tagline.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
		tagline.add_theme_color_override("font_outline_color", Color(0.33, 0.24, 0.12))
		tagline.add_theme_constant_override("outline_size", int(size * 0.14))
		column.add_child(tagline)
	column.reset_size()
	var margin := screen.y * 0.04
	column.position = Vector2((screen.x - column.size.x) * anchor.x,
			clampf((screen.y - column.size.y) * anchor.y, margin, screen.y - column.size.y - margin))
	_title_box = column


func _hide_title_box() -> void:
	if is_instance_valid(_title_box):
		_title_box.queue_free()
	_title_box = null
