class_name EventBalloon
extends Node3D
## Воздушный шар медленно пролетает над участком и над героем сбрасывает
## посылку на парашютике (PlotEvents.drop_parcel). Тень шара бежит по траве.

## Камера игры смотрит сверху узким углом (32°): высокое в кадр не
## попадает. Поэтому шар летит невысоко и ближе к камере, чем герой, —
## проплывает над ним поперёк экрана.
const HEIGHT := 2.8
## Насколько впереди героя (дальше от камеры; минус — ближе) он пролетает, метры.
const AHEAD := -3.0
const SPEED := 2.2
## Откуда и докуда летит, метры от героя.
const REACH := 18.0
const SCALE := 1.0
## Сколько секунд посылка спускается.
const FALL_TIME := 3.2

var _events: PlotEvents
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _landing := Vector3.ZERO
var _model: Node3D
var _travelled := 0.0
var _time := 0.0
var _dropped := false


static func spawn(events: PlotEvents, ahead: Vector3, direction: Vector3, landing: Vector3) -> EventBalloon:
	var balloon := EventBalloon.new()
	balloon.name = "Balloon"
	balloon._events = events
	balloon._landing = landing
	var over := landing + ahead * AHEAD + Vector3.UP * HEIGHT
	balloon._from = over - direction * REACH
	balloon._to = over + direction * REACH
	events.add_child(balloon)
	return balloon


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	var envelope := Models.place(_model, "hot_air_balloon", Vector3.ZERO, SCALE, randf() * TAU)
	envelope.set_meta("no_bake", true)
	_model.add_to_group("shadow_dynamic")
	Graphics.casters_changed.emit.call_deferred()
	global_position = _from


func _process(delta: float) -> void:
	_time += delta
	_travelled += SPEED * delta
	var length := _from.distance_to(_to)
	var t := _travelled / length
	global_position = _from.lerp(_to, t) + Vector3.UP * sin(_time * 0.9) * 0.25
	_model.rotation.y = sin(_time * 0.3) * 0.2
	if not _dropped and t >= 0.5:
		_dropped = true
		_drop()
	if t >= 1.0:
		queue_free()


func _drop() -> void:
	Sfx.play("pop", -6.0, 0.8)
	var parcel := Node3D.new()
	get_parent().add_child(parcel)
	for part in ["parcel", "parachute"]:
		Models.place(parcel, part, Vector3.ZERO, 1.0, 0.0, false).set_meta("no_bake", true)
	var from := global_position + Vector3.UP * 0.3
	parcel.global_position = from
	var tween := parcel.create_tween()
	tween.tween_method(func(t: float) -> void:
		# Спускается плавно, покачиваясь на стропах.
		parcel.global_position = from.lerp(_landing, t) + Vector3(sin(t * 9.0) * 0.4, 0.0, cos(t * 7.0) * 0.3) * (1.0 - t)
		parcel.rotation.z = sin(t * 9.0) * 0.25 * (1.0 - t), 0.0, 1.0, FALL_TIME)
	tween.tween_callback(func() -> void:
		parcel.queue_free()
		Juice.dust(get_parent(), _landing, 8)
		_events.drop_parcel(_landing))
