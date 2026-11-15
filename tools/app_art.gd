extends "res://tools/screenshots.gd"
## Значок игры и картинка загрузочного экрана — снимками из самой игры.
##
## Значок (1024×1024): герой с косилкой посередине идёт полосой, слева —
## скошенный полосами газон, справа — высокая трава. Без надписей и мелочей:
## он должен читаться и в 48 пикселях. Важное — в середине: Android
## обрезает значок кругом или скруглённым квадратом.
## Загрузочный экран (1920×1080): герой и ёжик в траве, сверху название.
## Растягивается «Cover» (обрезается по краям экрана), поэтому название
## и герой — ближе к середине.
##
## Запуск (нужен экран или xvfb):
##   xvfb-run -a -s "-screen 0 2560x1600x24" godot --path . \
##       --rendering-driver opengl3 --fixed-fps 30 --script tools/app_art.gd
## Картинки ложатся в assets/icons/ (icon.png, splash.png); значки Windows и
## macOS (icon.ico, icon.icns) из icon.png делает tools/make_app_icons.py.

const ART_OUT := "res://assets/icons"
const ICON_SIZE := Vector2i(1024, 1024)
const SPLASH_SIZE := Vector2i(1920, 1080)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_OUT))
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
	await _resize(SPLASH_SIZE)
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
	_hud.visible = false
	# Подписи на табличках калиток в картинках лишние.
	for label in _village.find_children("*", "Label3D", true, false):
		label.visible = false
	_player.set_physics_process(false)
	_hud.auto_reveal = false
	_build_overlay()
	var yard: Node3D = _village.get_node("Yard")
	var hedgehog: Node3D = yard.get_node("Hedgehog")
	hedgehog.set("_noticed", true)
	yard.complete_at = 1.01
	_camera.set_process(false)

	# --- Загрузочный экран: как обложка — полосы, герой, ёжик в траве.
	var hog := hedgehog.global_position
	_set_route(_serpentine(yard, [2.1, 2.85], 5.6, -5.6))
	while _advance(40.0, yard):
		pass
	_set_route(PackedVector2Array([_local(yard, hedgehog.position.x, 5.6),
			_local(yard, hedgehog.position.x, hedgehog.position.z + 2.3)]))
	_teleport()
	await _walk(yard, 2.0, 3.2)
	_place_camera(hog + Vector3(2.6, 2.7, -4.4), hog + Vector3(-0.15, 1.2, 1.9))
	_show_title_box(Vector2(0.5, 0.13), 150, true)
	await _save_art("splash", SPLASH_SIZE)
	_hide_title_box()

	# --- Значок: левая половина двора скошена полосами, герой идёт по краю
	# высокой травы к камере; камера сверху спереди — за героем только газон.
	await _resize(ICON_SIZE)
	_premow(yard, 0.5)
	_set_route(PackedVector2Array([_local(yard, 0.3, 5.0), _local(yard, 0.3, 0.6)]))
	_teleport()
	await _walk(yard, 2.0, 2.4)
	var hero := _player.global_position
	_place_camera(hero + Vector3(2.0, 5.0, -5.8), hero + Vector3(0.2, 0.5, -0.3))
	await frames(4)
	await _save_art("icon", ICON_SIZE)

	_state.clear()
	_state.graphics_quality = -1
	_state.language = ""
	quit()


func _save_art(file: String, size: Vector2i) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path("%s/%s.png" % [ART_OUT, file])
	image.save_png(path)
	print("ART %s %dx%d" % [path, image.get_width(), image.get_height()])
