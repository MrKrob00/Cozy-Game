class_name PinchZoom
extends Node
## Щипок двумя пальцами для масштаба камеры.

## -1 — приблизить, +1 — отдалить.
signal pinch_step(direction: int)

## Во сколько раз должно измениться расстояние между пальцами для одной ступени.
@export var step_ratio := 1.25

## true, пока на экране два пальца и больше.
var active := false

var _touches: Dictionary = {}
var _start_distance := 0.0


func _enter_tree() -> void:
	add_to_group("pinch_zoom")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		active = _touches.size() >= 2
		_start_distance = _distance() if active else 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if active:
			_update()


func _distance() -> float:
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _update() -> void:
	var distance := _distance()
	if _start_distance <= 0.0:
		_start_distance = distance
		return
	var ratio := distance / _start_distance
	if ratio > step_ratio:
		pinch_step.emit(-1)
		_start_distance = distance
	elif ratio < 1.0 / step_ratio:
		pinch_step.emit(1)
		_start_distance = distance
