extends SceneTree
## Снимает трейлер игры: сценарий ведёт героя, камеру, подписи и звук покадрово.
##
## Запуск (нужен экран или xvfb; кадры пишет сам Godot):
##   tools/make_trailer.sh
## Он запускает этот сценарий с записью кадров (--write-movie) и собирает
## кадры и звук в docs/trailer.mp4.
##
## Построение по советам монтажёров трейлеров (Derek Lieu): геймплей с первой
## секунды и сразу «крючок» — приятная полоса в высокой траве и ёжик на пути;
## затем понятно, что это за игра (цикл покоса); дальше содержимое по
## нарастанию: находки, новые участки, деревня, улучшения, праздник;
## название — в самом конце. «Показывай мечту, а не работу»: никаких меню.
##
## Монтаж идёт по музыке. Трек чуть ускорен, чтобы доля длилась ровно BEAT
## кадров; смены кадра стоят на границах тактов, подписи, прыжки ёжика,
## калитка, находки, залпы и название — на долях. Шаги героя тоже в темпе.
## Звук — фоном под музыкой, и только важное: ёжик, находки, «двор выкошен».
##
## Проверка без записи: TRAILER_PREVIEW=<папка> — каждый шестой кадр
## сохраняется картинкой, в журнал пишутся кадры событий.
##
## Игровые классы не используются как типы: скрипт компилируется раньше,
## чем регистрируются автозагрузки.

const FPS := 30.0
const CUT_LENGTH := 0.4
## Кадров на долю: 128,6 удара в минуту.
const BEAT := 14
## Уютная, тёплая: гитара и пианино, без тубы и барабанов.
const MUSIC := "res://assets/music/wholesome.ogg"
## Доля в записи трека, секунд (127,85 уд/мин): трек ускоряется до BEAT кадров.
const MUSIC_BEAT := 0.4693
## Первая доля в записи трека, секунд: с неё трек и начинается.
const MUSIC_FIRST_BEAT := 0.256
const MUSIC_VOLUME_DB := -4.0
## Звуки — тихо, под музыкой.
const SFX_VOLUME_DB := -15.0
## Свои голоса для звуков: игровые звуки в трейлере заглушены (при смене
## кадра и подготовке сцен игра выдаёт их пачками и невпопад), а трейлер
## ставит нужные сам — по долям и по событиям в кадре.
const VOICES := 10
## Скорость героя, при которой цикл шагов (два шага) длится ровно долю:
## анимация «walk» — 0,667 с при скорости 1,9 м/с.
const WALK_PACE := 0.6667 * 1.9 / (BEAT / FPS)
## Скорость покоса в ускоренном показе двора.
const LAPSE_PACE := 7.5
## Вспышка на смене кадра: прозрачность по кадрам от самой смены.
const FLASH := {-2: 0.3, -1: 0.65, 0: 0.85, 1: 0.55, 2: 0.3, 3: 0.12}
const FLASH_COLOR := Color(1.0, 0.97, 0.88)
## Дальше этой черты (мировая z) камера крючка не идёт: там забор двора.
const HOOK_CAMERA_STOP := -5.2
## Прыжок ёжика: полдоли.
const HOP_FRAMES := BEAT * 0.5

# Кадры смен: в долях, смены — на границах тактов (по 4 доли).
const AT_LAPSE := BEAT * 12
const AT_DONE := BEAT * 24
const AT_GATE := BEAT * 28
const AT_ROAD := BEAT * 32
const AT_SQUARE := BEAT * 40
const AT_ORCHARD := BEAT * 48
const AT_FESTIVAL := BEAT * 60
const AT_TITLE := BEAT * 64
const AT_END := BEAT * 72

var _village: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _hud: CanvasLayer
var _state: Node
var _sfx: Node
var _terrain: Node
var _placeholder: GDScript
var _juice: GDScript
var _fields: Array = []
var _caption: PanelContainer
var _caption_label: Label
var _overlay: CanvasLayer
var _flash: ColorRect
var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
# Находки, о которых звук уже был, и до какого кадра находки не озвучиваются
# (подготовка сцены открывает их пачкой).
var _found: Dictionary = {}
var _quiet_until := 0
# Находки двора: где на маршруте нож до них доходит (м) и на какой кадр
# (долю) это подогнано.
var _find_marks: Array[float] = []
var _find_frames: Dictionary = {}
var _find_sounds := false
# Кадр ролика (0 — первый) и дела, назначенные на кадры.
var _frame := 0
var _cues: Dictionary = {}
var _cuts: Array[int] = []
var _walk_pace := WALK_PACE
# Маршрут героя: точки (x, z) и пройденный по нему путь.
var _route := PackedVector2Array()
var _route_at := 0.0
var _route_length := 0.0
# Ёжик, уходящий с дороги.
var _hog: Node3D
var _hog_path: Array[Vector3] = []
var _hog_hops: Array[int] = []
var _hog_start := 0
# Проверка без записи.
var _preview := ""
var _seen: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	_preview = OS.get_environment("TRAILER_PREVIEW")
	_state = root.get_node("GameState")
	_sfx = root.get_node("Sfx")
	# Как при запекании карты: сохранение игрока трейлер не трогает.
	Engine.set_meta("baking_map", true)
	_state.clear()
	_state.title_seen = true
	_state.graphics_quality = 2
	# Трейлер на английском: и подписи, и интерфейс игры.
	_state.language = "en"
	_state.apply_language()
	_state.sound_enabled = true
	# Музыку ведёт сам трейлер (один трек, с нужного места и в нужном темпе).
	_state.music_enabled = false
	_state.settings_changed.emit()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
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
	_hud.get_node("%HintLabel").visible = false
	# Окно завершения участка в трейлере не показываем: только игра.
	_hud.get_node("%Completion").modulate.a = 0.0
	_hud.get_node("%Completion").mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Всплывающие подсказки игры идут с задержкой и в монтаже мешали бы
	# подписям трейлера; кнопку действия тоже прячем.
	# (У всплывающей панели игра сама анимирует modulate, поэтому гасим self_modulate.)
	_hud.get_node("%Toast").self_modulate.a = 0.0
	_hud.get_node("%ToastLabel").self_modulate.a = 0.0
	_hud.get_node("%ActionButton").self_modulate.a = 0.0
	_hud.get_node("%ActionButton").add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_player.set_physics_process(false)
	# Калитку трейлер показывает сам, в своём кадре.
	_hud.auto_reveal = false
	_build_overlay()
	_music = AudioStreamPlayer.new()
	_music.stream = load(MUSIC)
	_music.pitch_scale = MUSIC_BEAT / (BEAT / FPS)
	_music.volume_db = MUSIC_VOLUME_DB
	root.add_child(_music)
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		root.add_child(voice)
		_voices.append(voice)
	var yard: Node3D = _village.get_node("Yard")
	var garden: Node3D = _village.get_node("Garden")
	var square: Node3D = _village.get_node("Square")
	var orchard: Node3D = _village.get_node("Orchard")
	var hedgehog: Node3D = yard.get_node("Hedgehog")
	# Ёжика трейлер ведёт сам, по долям: игра его «замечать» не должна.
	hedgehog.set("_noticed", true)

	# Расписание: смены кадра, подписи и звуки — всё по долям.
	for cut: int in [AT_LAPSE, AT_DONE, AT_ROAD, AT_SQUARE, AT_ORCHARD, AT_FESTIVAL]:
		_cut_at(cut)
	_caption_at(BEAT, "Turn the overgrown into a cozy garden")
	_caption_at(AT_LAPSE + BEAT, "Mow it stripe by stripe")
	_caption_at(AT_LAPSE + BEAT * 4, "Find lost things in the grass")
	_caption_at(AT_DONE, "The yard is mowed!")
	_caption_at(AT_GATE, "Open up new places")
	_caption_at(AT_ROAD + BEAT, "A little village wakes up")
	_caption_at(AT_SQUARE + BEAT, "Upgrade your mower")
	_caption_at(AT_SQUARE + BEAT * 4, "Tame the weeds")
	_caption_at(AT_ORCHARD + BEAT, "Every garden has its own charm")
	for cut: int in [AT_LAPSE, AT_DONE, AT_ROAD, AT_SQUARE, AT_ORCHARD, AT_FESTIVAL]:
		_at(cut, _say.bind(""))
	# Двор выкошен: короткая мелодия на сильную долю.
	_at(AT_DONE, _play.bind("complete", SFX_VOLUME_DB + 2.0))

	# Заготовка: пара полос уже скошена, герой — в начале следующей, на ней
	# в высокой траве сидит ёжик.
	_set_route(_serpentine(yard, [2.1, 2.85], 5.6, -5.6))
	while _advance(40.0, yard):
		pass
	# Крючок рассчитан от ёжика: на 5-й доле косилка в 2,75 м от него.
	var notice_at := BEAT * 5
	var blade_start: float = hedgehog.position.z + 2.75 + WALK_PACE * notice_at / FPS
	_set_route(_serpentine(yard, [hedgehog.position.x, 4.35, 5.1, 5.85, 6.6], blade_start, -5.6))
	for find in get_nodes_in_group("find"):
		if yard.is_ancestor_of(find) and not find.call("is_collected"):
			var mark := _route_reach(Vector2(find.global_position.x, find.global_position.z),
					_player.get_cut_width() * 0.5 - 0.05)
			if mark >= 0.0:
				_find_marks.append(mark)
	_find_marks.sort()
	_advance(0.01, yard)
	_teleport()
	_advance(0.01, yard)
	_set_hud(false)
	_camera.set_process(false)
	_hook_camera(0.0)
	_hog_cues(hedgehog, notice_at, notice_at + BEAT)
	await frames(40)
	print("TRAILER_START ", Engine.get_frames_drawn())
	_music.play(MUSIC_FIRST_BEAT)
	_sync_steps(WALK_PACE)
	_fire()

	# 1. Крючок: косилка идёт сквозь высокую траву, за ней ровная полоса;
	# на пути ёжик — он пугается и прыжками уходит в свой уголок.
	while _frame < AT_LAPSE:
		_advance(WALK_PACE, yard)
		_hook_camera(_frame / float(AT_LAPSE))
		await _next()

	# 2. Цикл покоса: вид как в игре, двор покрывается полосами, находки.
	_set_hud(true)
	_follow_camera(1)
	_find_sounds = true
	while _frame < AT_DONE:
		_advance(_beat_pace(LAPSE_PACE), yard)
		await _next()
	_find_sounds = false

	# 3. Двор выкошен: конфетти, герой прыгает; камера уходит к новой калитке.
	_player.set("_current_speed", 0.0)
	_hush()
	yard.field.mow(yard.field.global_position, Vector3.FORWARD, 40.0, 40.0)
	var gate: Vector3 = garden.fence.get_gate_position() + Vector3.UP * 0.8
	_camera.set("_reveal_point", gate)
	var glide := BEAT * 2
	while _frame < AT_ROAD:
		var weight := smoothstep(0.0, 1.0, (_frame - (AT_GATE - glide)) / float(glide))
		_camera.set("_reveal_weight", weight)
		# 4. Калитка открывается ровно на сильную долю.
		if _frame == AT_GATE:
			garden.reveal()
		await _next()

	# 5. Дорога через деревню по стрелкам.
	var flyover = _camera.get("_flyover")
	if flyover:
		flyover.kill()
	_camera.set("_reveal_weight", 0.0)
	_camera.set("_yaw_offset", 0.0)
	_camera.set("_distance_offset", 0.0)
	_set_route(PackedVector2Array([Vector2(0.0, 9.8), Vector2(0.0, 19.5), Vector2(-2.6, 22.6),
			Vector2(-4.2, 25.4), Vector2(-9.0, 26.0), Vector2(-15.4, 26.0)]))
	_teleport()
	_follow_camera(2)
	while _frame < AT_SQUARE:
		_advance(5.2, null)
		await _next()

	# 6. Площадь: улучшенная косилка идёт сквозь бурьян. Один длинный кадр
	# вместо трёх коротких — видно и новую косилку, и что она умеет.
	_hush()
	_complete_silently(yard)
	garden.reveal()
	_complete_silently(garden)
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
	while _frame < AT_ORCHARD:
		_advance(WALK_PACE, square)
		var along := (_frame - AT_SQUARE) / float(AT_ORCHARD - AT_SQUARE)
		_chase_camera(Vector3(-3.3 + 0.5 * along, 2.1 + 0.5 * along, -4.6 - 0.5 * along), Vector3(0.0, 0.75 + 0.2 * along, -1.2))
		await _next()

	# 7. Фруктовый сад: деревья, пруд, полосы — вид как в игре.
	_hush()
	_complete_silently(square)
	square.get_node("Fountain").set_repaired(false)
	orchard.fence.set_gate_open(true, false)
	orchard.fence.call("_update_sign", orchard)
	_premow(orchard, 0.43)
	_set_hud(true)
	# Сад показан дольше: деревья, пруд, полосы на газоне.
	_set_route(_serpentine(orchard, [-1.6, -0.6, 0.4, 1.4], 8.0, -0.6))
	_teleport()
	_follow_camera(2)
	while _frame < AT_FESTIVAL:
		_advance(5.4, orchard)
		await _next()

	# 8. Финал: праздник в деревне, залпы по долям и название.
	_hush()
	_complete_silently(orchard)
	_set_hud(false)
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
	var volley := 0
	while _frame < AT_END:
		if _frame % (BEAT * 2) == 0:
			# Залпы конфетти через долю (без звука: звучит музыка), под
			# название — самый большой.
			var big := _frame == AT_TITLE
			for i in (3 if big else 2):
				var at := Vector3(-5.0 + ((volley * 5 + i * 4) % 11), 2.6 + (volley % 2) * 0.6, 23.0 + ((volley * 3 + i * 2) % 6))
				_juice.confetti(_village, at, 70 if big else 55)
				_juice.sparkle(_village, at, Color(1.0, 0.92, 0.6), 24)
			volley += 1
		if _frame == AT_TITLE:
			_show_title()
		if _frame >= AT_END - BEAT * 4:
			_music.volume_db = lerpf(MUSIC_VOLUME_DB, -40.0, (_frame - (AT_END - BEAT * 4)) / float(BEAT * 4))
		await _next()
	print("TRAILER_END ", Engine.get_frames_drawn())
	_state.clear()
	_state.graphics_quality = -1
	_state.language = ""
	quit()


# --- Кадры и расписание ---

# Дело на кадр ролика.
func _at(frame: int, action: Callable) -> void:
	if not _cues.has(frame):
		_cues[frame] = []
	_cues[frame].append(action)


# Следующий кадр: ждёт отрисовки текущего и выполняет дела нового.
func _next() -> void:
	if _preview != "" and _frame % 6 == 0:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg("%s/p%04d.jpg" % [_preview, _frame], 0.8)
	await process_frame
	_frame += 1
	_fire()


func _fire() -> void:
	for action: Callable in _cues.get(_frame, []):
		action.call()
	var alpha := 0.0
	for cut in _cuts:
		alpha = maxf(alpha, FLASH.get(_frame - cut, 0.0))
	_flash.color.a = alpha
	_move_hog()
	# Находка выпрыгнула из травы — её звук (только во дворе, тихо).
	for flag: String in _state.flags:
		if flag.begins_with("find_") and not _found.has(flag):
			_found[flag] = true
			if _find_sounds and _frame >= _quiet_until:
				_play("find", SFX_VOLUME_DB)
	if _preview != "":
		_log_events()


# Смена кадра: короткая светлая вспышка, без звука.
func _cut_at(frame: int) -> void:
	_cuts.append(frame)


func _caption_at(frame: int, text: String) -> void:
	_at(frame, _say.bind(text))


# Скорость покоса, при которой следующая находка выпрыгнет ровно на долю:
# доля выбирается один раз — ближайшая к тому, когда это вышло бы само.
func _beat_pace(base: float) -> float:
	for mark in _find_marks:
		if mark <= _route_at + 0.01:
			continue
		if not _find_frames.has(mark):
			var natural := _frame + (mark - _route_at) / (base / FPS)
			_find_frames[mark] = maxi(roundi(natural / BEAT) * BEAT, _frame + BEAT)
		var left: int = _find_frames[mark] - _frame
		return (mark - _route_at) / (maxi(left, 1) / FPS)
	return base


# Где на маршруте нож впервые проходит над точкой (в пределах reach), или −1.
func _route_reach(target: Vector2, reach: float) -> float:
	var along := 0.0
	while along < _route_length:
		var point: Vector2 = _route_point(along)[0]
		if point.distance_to(target) < reach:
			return along
		along += 0.02
	return -1.0


# Звук трейлера: имя как у игры (assets/audio), громкость и высота.
func _play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var variants: Array = _sfx.call("_variants", sound)
	if variants.is_empty():
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	# Вариант — по кадру, чтобы каждая запись звучала одинаково.
	voice.stream = variants[_frame % variants.size()]
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
	if _preview != "":
		print("SOUND %d %s %.0f dB" % [_frame, sound, volume_db])


# Подготовка сцены: находки, открытые ею разом, не озвучиваются.
func _hush() -> void:
	_quiet_until = _frame + 4


# Шаги героя с начала цикла и в темпе музыки.
func _sync_steps(pace: float) -> void:
	_walk_pace = pace
	var hero = _player.get("_hero")
	hero.play("push-walk", pace / 1.9, 0.0)
	hero.animation.seek(0.0, true)


# Журнал для подгонки: на каком кадре что случилось.
func _log_events() -> void:
	var now := {}
	for flag: String in ["find_shed_key", "find_yard_coins", "find_yard_duck", "find_square_key"]:
		now[flag] = _state.has_flag(flag)
	for plot_name: String in ["Yard", "Garden"]:
		now[plot_name + " completed"] = _village.get_node(plot_name).is_completed()
	now["garden gate"] = not _village.get_node("Garden").reveal_pending and _frame > AT_DONE
	for key: String in now:
		if now[key] and not _seen.has(key):
			_seen[key] = true
			print("EVENT %d %s" % [_frame, key])


# --- Ёжик ---

# Ёжик замечает косилку («!» и прыжок на месте), а долей позже прыжками
# уходит в свой уголок: по прыжку на полдоли.
func _hog_cues(animal: Node3D, notice_frame: int, leave_frame: int) -> void:
	# Вбок с дороги косилки — на уже скошенную полосу, где его хорошо видно, —
	# и дальше по ней. (В игре он уходит в свой уголок; тут это за кадром.)
	var aside := animal.global_position + Vector3(-1.5, 0.0, -0.5)
	_hog_path = [animal.global_position, aside, aside + Vector3(0.4, 0.0, -2.5)]
	_hog_hops = [2, 3]
	_hog_start = leave_frame
	_at(notice_frame, func() -> void:
		_play("squeak", SFX_VOLUME_DB + 1.0)
		_juice.floating_text(animal, animal.global_position + Vector3.UP * 0.9, "!", Color(1.0, 0.9, 0.4))
		animal.call("_hop_in_place"))
	_at(leave_frame, func() -> void:
		_hog = animal
		animal.set("_moved", true)
		animal.set("_busy", true)
		_state.set_flag("animal_" + animal.animal_id)
		animal.get("_body").process_mode = Node.PROCESS_MODE_DISABLED)


func _move_hog() -> void:
	if _hog == null:
		return
	var hop := (_frame - _hog_start) / HOP_FRAMES
	for part in _hog_hops.size():
		var hops := _hog_hops[part]
		var last := part == _hog_hops.size() - 1
		if hop < hops or last:
			var from := _hog_path[part]
			var to := _hog_path[part + 1]
			_hog.look_at(Vector3(to.x, _hog.global_position.y, to.z) + (to - from) * 0.01, Vector3.UP)
			_hog.call("_travel", minf(hop / hops, 1.0), from, to, hops)
			if last and hop >= hops:
				_hog.set("_busy", false)
				_juice.sparkle(_hog, _hog.global_position + Vector3.UP * 0.4, Color(1.0, 0.75, 0.8))
				_hog = null
			return
		hop -= hops


# --- Герой ---

func _set_route(points: PackedVector2Array) -> void:
	_route = points
	_route_at = 0.0
	_route_length = 0.0
	for i in points.size() - 1:
		_route_length += points[i].distance_to(points[i + 1])


# Точка маршрута на расстоянии along от начала и направление в ней.
func _route_point(along: float) -> Array:
	var left := clampf(along, 0.0, _route_length)
	for i in _route.size() - 1:
		var length := _route[i].distance_to(_route[i + 1])
		if left <= length or i == _route.size() - 2:
			var direction := (_route[i + 1] - _route[i]).normalized()
			return [_route[i] + direction * minf(left, length), direction]
		left -= length
	return [_route[0], Vector2(0.0, -1.0)]


# Ставит героя в начало маршрута без плавного доворота (смена кадра).
func _teleport() -> void:
	var start := _route_point(0.0)
	var at: Vector2 = start[0]
	var direction: Vector2 = start[1]
	_player.global_position = Vector3(at.x, _terrain.height_at(at), at.y)
	_player.rotation = Vector3(0.0, atan2(-direction.x, -direction.y), 0.0)
	_camera.set("_focus", _player.global_position)
	_camera.set("_ahead", Vector3.ZERO)


# Двигает героя по маршруту на один кадр и косит под ножом. Возвращает
# false, когда маршрут пройден.
func _advance(speed: float, plot) -> bool:
	var step := speed / FPS
	# Быстрый проход делится на шаги не длиннее ножа, чтобы не было пропусков.
	var parts := maxi(int(ceilf(step / (CUT_LENGTH * 0.7))), 1)
	var cutting := false
	for part in parts:
		_route_at += step / parts
		var point := _route_point(_route_at)
		var at: Vector2 = point[0]
		var direction: Vector2 = point[1]
		var yaw := atan2(-direction.x, -direction.y)
		_player.rotation.y = lerp_angle(_player.rotation.y, yaw, 0.45 if parts == 1 else 1.0)
		# Поворот — вокруг ножа, как в игре: точка маршрута — это нож.
		var forward := -_player.global_basis.z
		var body := Vector3(at.x, 0.0, at.y) - forward * 0.95
		_player.global_position = Vector3(body.x, _terrain.height_at(Vector2(body.x, body.z)), body.z)
		if plot:
			var units: float = plot.field.mow(_player.get_blade_position(), forward, _player.get_cut_width(),
					CUT_LENGTH, true)
			if units > 0.0:
				cutting = true
				_state.add_grass(units * 0.4)
				if _state.bag_fill > _state.bag_capacity * 0.8:
					_state.empty_bag()
	var pusher: Vector3 = _player.global_position - _player.global_basis.z * 0.57
	for field in _fields:
		field.set_pusher_position(pusher)
	_placeholder.set_pusher(pusher)
	_player.set("_current_speed", _walk_pace)
	_player.set("_cutting", cutting)
	var clippings = _player.get("_clippings")
	if is_instance_valid(clippings):
		clippings.emitting = cutting
	_player.call("_update_interaction", 1.0 / FPS)
	return _route_at < _route_length


# Маршрут «змейкой» по участку: полосы на местных x (lanes) между местными
# z from и to, развороты дугой.
func _serpentine(plot: Node3D, lanes: Array, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in lanes.size():
		var start := from if i % 2 == 0 else to
		var end := to if i % 2 == 0 else from
		points.append(_local(plot, lanes[i], start))
		points.append(_local(plot, lanes[i], end))
		if i < lanes.size() - 1:
			var middle: float = (lanes[i] + lanes[i + 1]) * 0.5
			var radius: float = absf(lanes[i + 1] - lanes[i]) * 0.5
			var out := signf(end - start)
			for k in range(1, 6):
				var angle := PI * k / 6.0
				points.append(_local(plot, middle - cos(angle) * (lanes[i + 1] - lanes[i]) * 0.5,
						end + out * sin(angle) * radius))
	return points


func _local(plot: Node3D, x: float, z: float) -> Vector2:
	var world := plot.to_global(Vector3(x, 0.0, z))
	return Vector2(world.x, world.z)


# Участок считается выкошенным без торжества (смена кадра в монтаже).
func _complete_silently(plot: Node3D) -> void:
	var state: Dictionary = plot.get("_state")
	state["completed"] = true
	state["tidy"] = true
	state["milestones"] = [25, 50, 75]
	plot.field.mow(plot.field.global_position, Vector3.FORWARD, 80.0, 80.0)
	plot.call("_light_up")
	plot.fence.call("_update_sign", plot)


# Часть участка уже скошена полосами (share — доля ширины), без наград.
func _premow(plot: Node3D, share: float) -> void:
	var state: Dictionary = plot.get("_state")
	state["milestones"] = [25, 50, 75]
	var half: Vector2 = plot.field.size * 0.5
	var x := -half.x + 0.4
	var lane := 0
	while x < -half.x + plot.field.size.x * share:
		var z := -half.y
		while z < half.y:
			var forward: Vector3 = plot.global_basis.z * (1.0 if lane % 2 == 0 else -1.0)
			plot.field.mow(plot.to_global(Vector3(x, 0.0, z)), forward, 1.1, 0.5, false)
			z += 0.35
		x += 1.05
		lane += 1


# --- Камера ---

# Камера рядом с героем: offset и look — в его координатах (−Z вперёд).
func _chase_camera(offset: Vector3, look: Vector3) -> void:
	var basis := _player.global_basis
	var origin := _player.global_position
	_camera.global_position = origin + basis * offset
	_camera.look_at(origin + basis * look, Vector3.UP)


# Камера крючка: сначала рядом с героем, затем отходит вперёд и опускает
# взгляд на траву перед косилкой — туда, где сидит ёжик. along — 0…1.
func _hook_camera(along: float) -> void:
	var swing := smoothstep(0.1, 0.5, along)
	var look := Vector3(0.0, 0.75, -0.7).lerp(Vector3(0.0, 0.4, -2.3), swing)
	_chase_camera(Vector3(2.9, 1.5, -4.6).lerp(Vector3(3.0, 2.1, -5.7), swing), look)
	# У дальнего забора камера останавливается, и герой подходит к ней сам;
	# взгляд при этом возвращается с травы на косилку.
	var past := HOOK_CAMERA_STOP - _camera.global_position.z
	if past > 0.0:
		_camera.global_position.z = HOOK_CAMERA_STOP
		look = look.lerp(Vector3(0.0, 0.65, -0.9), smoothstep(0.0, 2.5, past))
		_camera.look_at(_player.global_position + _player.global_basis * look, Vector3.UP)


# Обычная игровая камера на ступени масштаба zoom.
func _follow_camera(zoom: int) -> void:
	_camera.zoom_index = zoom
	_camera.set("_distance", _camera.zoom_distances[zoom])
	_camera.set("_focus", _player.global_position)
	_camera.set("_ahead", Vector3.ZERO)
	_camera.set_process(true)


# --- Подписи ---

func _set_hud(shown: bool) -> void:
	_hud.get_node("%Margin").visible = shown


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 60
	root.add_child(_overlay)
	_caption = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.96, 0.86, 0.96)
	box.set_corner_radius_all(28)
	box.content_margin_left = 44.0
	box.content_margin_right = 44.0
	box.content_margin_top = 18.0
	box.content_margin_bottom = 22.0
	box.shadow_color = Color(0.2, 0.14, 0.08, 0.35)
	box.shadow_size = 10
	_caption.add_theme_stylebox_override("panel", box)
	_caption_label = Label.new()
	_caption_label.add_theme_font_size_override("font_size", 58)
	_caption_label.add_theme_color_override("font_color", Color(0.27, 0.22, 0.17))
	_caption.add_child(_caption_label)
	_caption.visible = false
	_overlay.add_child(_caption)
	_flash = ColorRect.new()
	_flash.color = Color(FLASH_COLOR, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_flash)


# Подпись внизу экрана; пустая строка её убирает.
func _say(text: String) -> void:
	if text == "":
		_caption.visible = false
		return
	_caption_label.text = text
	_caption.visible = true
	_caption.reset_size()
	var screen := root.get_visible_rect().size
	_caption.position = Vector2((screen.x - _caption.size.x) * 0.5, screen.y - _caption.size.y - 70.0)
	_caption.pivot_offset = _caption.size * 0.5
	_caption.scale = Vector2.ONE * 0.6
	var tween := _caption.create_tween()
	tween.tween_property(_caption, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Название игры и слоган в конце.
func _show_title() -> void:
	var screen := root.get_visible_rect().size
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	_overlay.add_child(column)
	var title := Label.new()
	title.text = "Cozy Grass Cut"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 170)
	title.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	title.add_theme_color_override("font_outline_color", Color(0.33, 0.24, 0.12))
	title.add_theme_constant_override("outline_size", 40)
	column.add_child(title)
	var tagline := Label.new()
	tagline.text = "One cozy stripe at a time"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 64)
	tagline.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	tagline.add_theme_color_override("font_outline_color", Color(0.33, 0.24, 0.12))
	tagline.add_theme_constant_override("outline_size", 22)
	column.add_child(tagline)
	title.pivot_offset = Vector2(screen.x * 0.5, 110.0)
	title.scale = Vector2.ONE * 1.6
	title.modulate.a = 0.0
	tagline.modulate.a = 0.0
	var tween := title.create_tween()
	tween.tween_property(title, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(tagline, "modulate:a", 1.0, 0.35)
