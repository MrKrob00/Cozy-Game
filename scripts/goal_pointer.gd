class_name GoalPointer
extends Control
## Стрелка у края экрана: куда идти дальше. Указывает на калитку первого
## открытого, но ещё не выкошенного участка, пока она за кадром.

const MARGIN := 70.0
const SIZE := 34.0
const COLOR := Color(1.0, 0.80, 0.25)
const OUTLINE := Color(0.36, 0.26, 0.12)

var target: Plot

var _time := 0.0
var _point := Vector2.ZERO
var _angle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_time += delta
	target = _next_goal()
	visible = false
	var camera := get_viewport().get_camera_3d()
	if target == null or camera == null or target.fence == null:
		return
	var gate := target.fence.get_gate_position() + Vector3.UP * 1.0
	var screen := get_viewport_rect().size
	var on_screen := camera.unproject_position(gate)
	var behind := camera.is_position_behind(gate)
	var inner := Rect2(Vector2.ZERO, screen).grow(-MARGIN)
	if not behind and inner.has_point(on_screen):
		return
	# Переводим из пикселей окна в координаты интерфейса.
	var scale := size / screen
	var center := size * 0.5
	var direction := (on_screen * scale - center)
	if behind:
		direction = -direction
	if direction.length() < 1.0:
		return
	direction = direction.normalized()
	var half := size * 0.5 - Vector2.ONE * MARGIN
	var reach := minf(absf(half.x / direction.x) if absf(direction.x) > 0.001 else INF,
			absf(half.y / direction.y) if absf(direction.y) > 0.001 else INF)
	_point = center + direction * reach - direction * sin(_time * 5.0) * 8.0
	_angle = direction.angle()
	visible = true
	queue_redraw()


func _draw() -> void:
	var tip := Vector2(SIZE, 0.0).rotated(_angle)
	var left := Vector2(-SIZE * 0.6, -SIZE * 0.75).rotated(_angle)
	var right := Vector2(-SIZE * 0.6, SIZE * 0.75).rotated(_angle)
	var points := PackedVector2Array([_point + tip, _point + left, _point + right])
	draw_colored_polygon(points, COLOR)
	points.append(points[0])
	draw_polyline(points, OUTLINE, 4.0, true)


# Цель — первый по цепочке участок, который открыт и не выкошен, и игрок не на нём.
func _next_goal() -> Plot:
	var village := get_tree().get_first_node_in_group("village") as Village
	for node in get_tree().get_nodes_in_group("plot"):
		var plot := node as Plot
		if plot.is_unlocked() and not plot.is_completed():
			if village and village.current_plot == plot and plot.get_progress() > 0.0:
				return null
			if plot.plot_id == "yard":
				return null
			return plot
	return null
