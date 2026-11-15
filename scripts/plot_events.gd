class_name PlotEvents
extends Node3D
## Небольшие события, чтобы деревня жила, пока косишь.
##
## У каждого участка свои три события по времени (отсчёт свой, пока участок
## текущий и не выкошен; каждое — один раз за игру), 1:30 / 3:00 / 5:00:
##   двор — клевер-четырёхлистник, грибной дождик, воздушный шар с подарком;
##   сад бабушки — кот за бабочкой, пчёлы над клумбами, кролик с морковкой;
##   площадь — почтальон роняет письмо, голуби, радуга над фонтаном (ждёт
##   починки фонтана и случается сразу после неё);
##   фруктовый сад — лягушачий хор, гость на лавочке, яблокопад.
## Раз в 2–3 минуты — случайное: стая птиц, порыв ветра с листьями, а ещё
## дождик, кот за бабочкой, почтальон и яблокопад, когда каждый уже был
## событием своего участка. Проигрыша нет: только приятная неожиданность и
## иногда немного монет.

## Секунды на участке, когда случаются его события.
const TIMES := [90.0, 180.0, 300.0]
const SCHEDULE := {
	"yard": ["clover", "rain", "balloon"],
	"garden": ["cat", "bees", "rabbit"],
	"square": ["letter", "pigeons", "rainbow"],
	"orchard": ["frogs", "bench", "apples"],
}
## Случайные события: раз в столько секунд (от и до).
const AMBIENT_EVERY := Vector2(120.0, 180.0)
const AMBIENT := ["birds", "wind"]
## Становятся случайными, когда уже случились событием своего участка (флаг).
const UNLOCKS := {"rain": "event_yard_1", "cat": "event_garden_0", "letter": "event_square_0",
		"apples": "event_orchard_2"}
const RAINBOW_FLAG := "event_square_2"
## Случайное не начинается, если до события по времени меньше этого.
const AMBIENT_GAP := 25.0

const RAIN_TIME := 30.0
## После дождика трава ещё столько секунд мокрая (последняя треть — сохнет).
const WET_AFTER := 60.0
## За сколько секунд трава намокает, когда пошёл дождик.
const WET_RISE := 4.0
const CLOVER_TIME := 30.0
const CLOVER_COINS := 10
const LETTER_COINS := 15
const PARCEL_COINS := 25

## Сколько секунд игрок провёл на каждом участке (за этот запуск).
var plot_time: Dictionary = {}
## Идёт ли дождик.
var raining := false
## Насколько мокрая трава сейчас (0–1).
var wetness := 0.0

var _village: Village
var _player: Player
var _ambient_timer := 0.0
var _last_ambient := ""
var _rain: CPUParticles3D
var _rain_left := 0.0
var _rain_sound: LoopSound
var _dry_left := 0.0
var _applied_wetness := 0.0


func _ready() -> void:
	_village = get_parent() as Village
	_player = get_tree().get_first_node_in_group("player") as Player
	_ambient_timer = randf_range(AMBIENT_EVERY.x, AMBIENT_EVERY.y)
	var square := _village.get_node_or_null("Square") if _village else null
	var repair := square.get_node_or_null("FountainRepair") as Repairable if square else null
	if repair:
		repair.repaired.connect(_on_fountain_repaired)


func _process(delta: float) -> void:
	if _rain:
		_update_rain(delta)
	_update_wetness(delta)
	# Время идёт, только пока игрок играет (не титульный экран, не показ калитки).
	if _player == null or not _player.controls_enabled or _village == null:
		return
	var plot := _village.current_plot
	if plot and plot.is_unlocked() and not plot.is_completed() and SCHEDULE.has(plot.plot_id):
		var time: float = plot_time.get(plot.plot_id, 0.0) + delta
		plot_time[plot.plot_id] = time
		var kinds: Array = SCHEDULE[plot.plot_id]
		for i in TIMES.size():
			var flag := "event_%s_%d" % [plot.plot_id, i]
			if time >= TIMES[i] and not GameState.has_flag(flag):
				# Радуга — только над работающим фонтаном: иначе ждёт починки.
				if kinds[i] == "rainbow" and not _fountain_repaired():
					continue
				GameState.set_flag(flag)
				fire(kinds[i])
				break
	_ambient_timer -= delta
	if _ambient_timer <= 0.0:
		_ambient_timer = randf_range(AMBIENT_EVERY.x, AMBIENT_EVERY.y)
		if _seconds_to_timed() > AMBIENT_GAP:
			_fire_ambient()


## Запускает событие по имени (по времени, случайное, или из проверок).
func fire(kind: String) -> bool:
	match kind:
		"letter":
			return _letter()
		"rain":
			return _start_rain()
		"balloon":
			return _balloon()
		"clover":
			return _clover()
		"cat":
			return _cat()
		"birds":
			EventBirds.spawn(self, _player.global_position, _away_direction())
			return true
		"wind":
			return _wind()
		"bees":
			return EventBees.start(self, _village.get_node_or_null("Garden"))
		"rabbit":
			return _rabbit()
		"pigeons":
			return _pigeons()
		"rainbow":
			return EventRainbow.start(self, _fountain())
		"frogs":
			return EventFrogs.start(self, _village.get_node_or_null("Orchard"))
		"bench":
			return EventVisitor.start(self, _village.get_node_or_null("Orchard"))
		"apples":
			return EventApples.start(self, _player)
	return false


# Сколько секунд до ближайшего ещё не случившегося события по времени.
func _seconds_to_timed() -> float:
	var plot := _village.current_plot
	if plot == null or plot.is_completed():
		return INF
	if not SCHEDULE.has(plot.plot_id):
		return INF
	var time: float = plot_time.get(plot.plot_id, 0.0)
	for i in TIMES.size():
		if not GameState.has_flag("event_%s_%d" % [plot.plot_id, i]):
			return TIMES[i] - time
	return INF


## Какие случайные события сейчас возможны: всегдашние и уже открытые.
func ambient_kinds() -> Array:
	var kinds := AMBIENT.duplicate()
	for kind: String in UNLOCKS:
		if GameState.has_flag(UNLOCKS[kind]):
			kinds.append(kind)
	return kinds


func _fire_ambient() -> void:
	var kinds := ambient_kinds()
	kinds.erase(_last_ambient)
	kinds.shuffle()
	for kind: String in kinds:
		if fire(kind):
			_last_ambient = kind
			return


# Случайное направление по земле (куда летят птицы, дует ветер, бежит кот).
func _away_direction() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)


# Место в нескошенной траве текущего участка, недалеко от героя, но не под
# самой косилкой. Null — нескошенной травы рядом нет.
func _uncut_spot(near: float, far: float) -> Variant:
	var plot := _village.current_plot
	if plot == null or plot.is_completed() or plot.field == null:
		return null
	var at := _player.global_position
	var camera := get_viewport().get_camera_3d()
	var screen := get_viewport().get_visible_rect().size
	var best: Variant = null
	var best_score := INF
	for spot in plot.field.get_uncut_positions(160):
		var distance := Vector2(spot.x - at.x, spot.z - at.z).length()
		if distance < near:
			continue
		# Только там, где его видно: не у краёв экрана и не под сообщениями сверху.
		if camera and screen.x > 0.0:
			var on_screen := camera.unproject_position(spot + Vector3.UP * 0.6) / screen
			if camera.is_position_behind(spot) or on_screen.x < 0.15 or on_screen.x > 0.85 \
					or on_screen.y < 0.3 or on_screen.y > 0.85:
				continue
		var score := absf(distance - (near + far) * 0.5) + (100.0 if distance > far else 0.0)
		if score < best_score:
			best_score = score
			best = spot
	return best


# Открытое место на участке рядом с героем (для посылки с шара).
func _open_spot() -> Vector3:
	var plot := _village.current_plot
	var at := _player.global_position
	var rect := plot.get_inner_rect().grow(-1.0) if plot else Rect2(Vector2(at.x, at.z), Vector2.ZERO)
	var spot := Vector2(at.x, at.z) + Vector2.from_angle(randf() * TAU) * randf_range(2.0, 3.5)
	spot = spot.clamp(rect.position, rect.end)
	return Vector3(spot.x, plot.global_position.y if plot else at.y, spot.y)


# --- 1:30 — письмо от почтальона ---

func _letter() -> bool:
	var plot := _village.current_plot
	if plot == null:
		return false
	var spot: Variant = _uncut_spot(2.0, 6.0)
	var landing: Vector3 = spot if spot != null else _open_spot()
	# Без сообщения: почтальона слышно (шаги), письмо видно в полёте.
	EventPostman.spawn(self, plot, _player.global_position, landing)
	return true


## Письмо долетело до земли (зовёт EventPostman).
func drop_letter(landing: Vector3) -> void:
	EventGift.spawn(self, "letter", landing, LETTER_COINS, "",
			_village.current_plot.field if _village.current_plot else null)


# --- 3:00 — грибной дождик ---

func _start_rain() -> bool:
	if raining:
		return false
	raining = true
	_rain_left = RAIN_TIME
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 420
	_rain.lifetime = 0.7
	_rain.local_coords = false
	var drop := BoxMesh.new()
	drop.size = Vector3(0.018, 0.34, 0.018)
	_rain.mesh = drop
	var water := StandardMaterial3D.new()
	water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color = Color(0.86, 0.94, 1.0, 0.55)
	_rain.material_override = water
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(9.0, 0.1, 9.0)
	_rain.direction = Vector3(0.12, -1.0, 0.05)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 11.0
	_rain.initial_velocity_max = 13.0
	_rain.gravity = Vector3.ZERO
	add_child(_rain)
	_rain.emitting = true
	_rain_sound = LoopSound.create("rain", -16.0)
	add_child(_rain_sound)
	return true


func _update_rain(delta: float) -> void:
	_rain.global_position = _player.global_position + Vector3(-0.8, 7.0, -0.4)
	if not raining:
		return
	_rain_left -= delta
	if _rain_left <= 0.0:
		raining = false
		_dry_left = WET_AFTER
		_rain.emitting = false
		if _rain_sound:
			_rain_sound.fade_out()
			_rain_sound = null
		Juice.sparkle(self, _player.global_position + Vector3.UP * 0.4, Color(0.8, 0.95, 1.0), 24)
		var finished := _rain
		_rain = null
		get_tree().create_timer(1.0).timeout.connect(finished.queue_free)


# Трава намокает за несколько секунд дождя, после него ещё минуту мокрая
# и в росе, последнюю треть — постепенно сохнет.
func _update_wetness(delta: float) -> void:
	if raining:
		wetness = minf(wetness + delta / WET_RISE, 1.0)
	elif _dry_left > 0.0:
		_dry_left -= delta
		wetness = clampf(_dry_left / (WET_AFTER / 3.0), 0.0, 1.0)
	else:
		wetness = 0.0
	if absf(wetness - _applied_wetness) < 0.01 and not (wetness == 0.0 and _applied_wetness > 0.0):
		return
	_applied_wetness = wetness
	for field in get_tree().get_nodes_in_group("mow_field"):
		(field as MowField).set_wetness(wetness)


# --- 5:00 — воздушный шар с посылкой ---

func _balloon() -> bool:
	if _village.current_plot == null:
		return false
	# Шар летит поперёк экрана чуть впереди героя: сверху камера его иначе не видит.
	var camera := get_viewport().get_camera_3d()
	var ahead := Vector3.FORWARD
	if camera:
		ahead = -camera.global_basis.z
		ahead.y = 0.0
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	EventBalloon.spawn(self, ahead, ahead.cross(Vector3.UP), _open_spot())
	return true


## Посылка с шара приземлилась (зовёт EventBalloon).
func drop_parcel(landing: Vector3) -> void:
	EventGift.spawn(self, "parcel", landing, PARCEL_COINS, "", null)


# --- Случайные ---

func _clover() -> bool:
	var spot: Variant = _uncut_spot(3.0, 7.0)
	if spot == null:
		return false
	EventClover.spawn(self, spot, _village.current_plot.field, CLOVER_TIME, CLOVER_COINS)
	if not GameState.has_flag("hint_clover"):
		GameState.set_flag("hint_clover")
		GameState.toast("В траве клевер-четырёхлистник! Скосите его, пока не завял")
	return true


func _cat() -> bool:
	if _village.current_plot == null:
		return false
	EventCat.spawn(self, _player, _away_direction())
	return true


func _wind() -> bool:
	var direction := _away_direction()
	var at := _player.global_position
	var gust := CPUParticles3D.new()
	gust.name = "Gust"
	gust.amount = 34
	gust.lifetime = 3.2
	gust.one_shot = true
	gust.explosiveness = 0.3
	gust.local_coords = false
	gust.mesh = Models.mesh("fx_leaf")
	gust.material_override = Placeholder.material(Color.WHITE)
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.4, 0.75])
	colors.colors = PackedColorArray([Color(0.62, 0.84, 0.32).srgb_to_linear(),
			Color(0.94, 0.80, 0.30).srgb_to_linear(), Color(0.95, 0.60, 0.26).srgb_to_linear()])
	gust.color_initial_ramp = colors
	gust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	gust.emission_box_extents = Vector3(7.0, 1.2, 0.5)
	gust.direction = Vector3(0.0, 0.15, -1.0)
	gust.spread = 12.0
	gust.initial_velocity_min = 4.5
	gust.initial_velocity_max = 7.0
	gust.gravity = Vector3(0.0, -0.6, 0.0)
	gust.angular_velocity_min = -300.0
	gust.angular_velocity_max = 300.0
	gust.scale_amount_min = 1.2
	gust.scale_amount_max = 1.7
	add_child(gust)
	# Облако листьев выходит с наветренной стороны и пролетает над героем.
	gust.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), at - direction * 9.0 + Vector3.UP * 1.6)
	gust.emitting = true
	get_tree().create_timer(gust.lifetime + 1.0).timeout.connect(gust.queue_free)
	# Трава гнётся сильнее, пока дует.
	for field in get_tree().get_nodes_in_group("mow_field"):
		(field as MowField).gust(4.0)
	return true


# --- Площадь: фонтан ---

func _fountain() -> Node3D:
	var square := _village.get_node_or_null("Square") if _village else null
	return square.get_node_or_null("Fountain") as Node3D if square else null


func _fountain_repaired() -> bool:
	var square := _village.get_node_or_null("Square") if _village else null
	var repair := square.get_node_or_null("FountainRepair") as Repairable if square else null
	return repair != null and repair.is_repaired()


# Фонтан починили: если радуги ещё не было — она сразу (через миг) над ним.
func _on_fountain_repaired() -> void:
	if GameState.has_flag(RAINBOW_FLAG):
		return
	await get_tree().create_timer(2.0).timeout
	GameState.set_flag(RAINBOW_FLAG)
	fire("rainbow")


func _rabbit() -> bool:
	var spot: Variant = _uncut_spot(3.0, 6.5)
	if spot == null:
		return false
	EventRabbit.spawn(self, spot, _village.current_plot.field)
	return true


func _pigeons() -> bool:
	var plot := _village.current_plot
	if plot == null:
		return false
	EventPigeons.spawn(self, plot, _player)
	return true
