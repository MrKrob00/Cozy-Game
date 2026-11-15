class_name EventPostman
extends Node3D
## Почтальон торопится мимо участка (за забором), и из его сумки выпадает
## письмо: ветер уносит его в траву участка (PlotEvents.drop_letter).

const SPEED := 2.6

var _events: PlotEvents
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _landing := Vector3.ZERO
## Где на пути (0–1) письмо выпадает: ближе всего к месту падения.
var _drop_at := 0.5
var _figure: CharacterModel
var _travelled := 0.0
var _dropped := false
var _terrain: Terrain


## Почтальон бежит по ближайшей к герою дороге из конца в конец (а не вдоль
## забора: так он шёл прямо по нему).
static func spawn(events: PlotEvents, _plot: Plot, near: Vector3, landing: Vector3) -> EventPostman:
	var postman := EventPostman.new()
	postman.name = "PostmanRun"
	postman._events = events
	postman._landing = landing
	var terrain := events.get_tree().get_first_node_in_group("terrain") as Terrain
	var point := Vector2(near.x, near.z)
	var road: Dictionary = {}
	var nearest := INF
	if terrain:
		for candidate: Dictionary in terrain.roads:
			var rect: Rect2 = candidate["rect"]
			var distance := point.distance_to(point.clamp(rect.position, rect.end))
			if distance < nearest:
				nearest = distance
				road = candidate
	if road.is_empty():
		postman._from = near + Vector3(-9.0, 0.0, 3.0)
		postman._to = near + Vector3(9.0, 0.0, 3.0)
	else:
		var rect: Rect2 = road["rect"]
		var middle := rect.get_center()
		var ends: Array[Vector2] = []
		if road["axis"] == "x":
			ends = [Vector2(rect.position.x, middle.y), Vector2(rect.end.x, middle.y)]
		else:
			ends = [Vector2(middle.x, rect.position.y), Vector2(middle.x, rect.end.y)]
		if randf() < 0.5:
			ends.reverse()
		postman._from = Vector3(ends[0].x, 0.0, ends[0].y)
		postman._to = Vector3(ends[1].x, 0.0, ends[1].y)
	var path := postman._to - postman._from
	var along := (landing - postman._from).dot(path) / maxf(path.length_squared(), 0.01)
	postman._drop_at = clampf(along, 0.15, 0.85)
	events.add_child(postman)
	return postman


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	_figure = CharacterModel.create("res://assets/characters/postman.glb", 1.5)
	# Модель смотрит на +Z, а идём «вперёд» по −Z.
	_figure.rotation.y = PI
	add_child(_figure)
	_figure.play("sprint" if _figure.animation and _figure.animation.has_animation("sprint") else "walk", 1.0, 0.0)
	_place(0.0)
	var direction := _to - _from
	rotation.y = atan2(-direction.x, -direction.z)


func _process(delta: float) -> void:
	_travelled += SPEED * delta
	var length := _from.distance_to(_to)
	_place(_travelled / length)
	if not _dropped and _travelled >= length * _drop_at:
		_dropped = true
		_throw_letter()
	if _travelled >= length:
		queue_free()


func _place(t: float) -> void:
	var at := _from.lerp(_to, clampf(t, 0.0, 1.0))
	at.y = _terrain.height_at(Vector2(at.x, at.z)) if _terrain else _landing.y
	global_position = at


# Письмо выпархивает из сумки и, кружась, летит дугой в траву.
func _throw_letter() -> void:
	Sfx.play("pop", -8.0, 1.3)
	var letter := Models.place(get_parent(), "letter", Vector3.ZERO, 1.0, 0.0, false)
	letter.set_meta("no_bake", true)
	var from := global_position + Vector3.UP * 1.0
	letter.global_position = from
	# Почтальон убегает раньше, чем письмо долетит: дальше — только локальные
	# значения (обращение к нему после queue_free падало бы).
	var events := _events
	var landing := _landing
	# Дорога может быть далеко от места падения: дуга тем выше и дольше.
	var distance := from.distance_to(landing)
	var lift := 1.2 + distance * 0.15
	var tween := letter.create_tween()
	tween.tween_method(func(t: float) -> void:
		letter.global_position = from.lerp(landing, t) + Vector3.UP * lift * 4.0 * t * (1.0 - t)
		letter.rotation = Vector3(sin(t * 9.0) * 0.6, t * 8.0, cos(t * 7.0) * 0.5), 0.0, 1.0,
			clampf(distance / 6.0, 1.2, 2.4))
	tween.tween_callback(func() -> void:
		letter.queue_free()
		if is_instance_valid(events):
			events.drop_letter(landing))
