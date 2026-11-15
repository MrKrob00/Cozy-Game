class_name EventPostman
extends Node3D
## Почтальон торопится мимо участка (за забором), и из его сумки выпадает
## письмо: ветер уносит его в траву участка (PlotEvents.drop_letter).

const SPEED := 2.6
## Сколько метров он пробегает в каждую сторону от героя.
const REACH := 9.0
## Насколько он дальше края участка, метры.
const OUTSIDE := 1.4

var _events: PlotEvents
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _landing := Vector3.ZERO
var _figure: CharacterModel
var _travelled := 0.0
var _dropped := false
var _terrain: Terrain


static func spawn(events: PlotEvents, plot: Plot, near: Vector3, landing: Vector3) -> EventPostman:
	var postman := EventPostman.new()
	postman.name = "PostmanRun"
	postman._events = events
	postman._landing = landing
	# Ближайшая к герою сторона участка; почтальон бежит вдоль неё снаружи.
	var rect := plot.get_inner_rect()
	var point := Vector2(near.x, near.z)
	var sides := [
		[point.x - rect.position.x, Vector2(rect.position.x - OUTSIDE, point.y), Vector2(0, 1)],
		[rect.end.x - point.x, Vector2(rect.end.x + OUTSIDE, point.y), Vector2(0, 1)],
		[point.y - rect.position.y, Vector2(point.x, rect.position.y - OUTSIDE), Vector2(1, 0)],
		[rect.end.y - point.y, Vector2(point.x, rect.end.y + OUTSIDE), Vector2(1, 0)],
	]
	sides.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var middle: Vector2 = sides[0][1]
	var along: Vector2 = sides[0][2] * (1.0 if randf() < 0.5 else -1.0)
	postman._from = Vector3(middle.x - along.x * REACH, 0.0, middle.y - along.y * REACH)
	postman._to = Vector3(middle.x + along.x * REACH, 0.0, middle.y + along.y * REACH)
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
	if not _dropped and _travelled >= length * 0.5:
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
	var tween := letter.create_tween()
	tween.tween_method(func(t: float) -> void:
		letter.global_position = from.lerp(_landing, t) + Vector3.UP * 1.6 * 4.0 * t * (1.0 - t)
		letter.rotation = Vector3(sin(t * 9.0) * 0.6, t * 8.0, cos(t * 7.0) * 0.5), 0.0, 1.0, 1.4)
	tween.tween_callback(func() -> void:
		letter.queue_free()
		_events.drop_letter(_landing))
