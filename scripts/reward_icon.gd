class_name RewardIcon
extends Control
## Значок награды, который летит из мира к счётчику: монетка или листик компоста.
## Рисуется сам (_draw), без картинок и шрифтовых значков.

enum Kind { COIN, LEAF }

const SIZE := 60.0

var kind := Kind.COIN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ONE * SIZE
	pivot_offset = size * 0.5


func _draw() -> void:
	if kind == Kind.COIN:
		draw_coin(self, size * 0.5, SIZE * 0.42)
	else:
		draw_leaf(self, size * 0.5, SIZE * 0.42)


## Монетка: её же рисует значок у счётчика (HudIcon).
static func draw_coin(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	var line := maxf(radius * 0.12, 1.5)
	canvas.draw_circle(center + Vector2(0.0, radius * 0.12), radius, Color(0.55, 0.38, 0.12, 0.5))
	canvas.draw_circle(center, radius, Color(0.98, 0.76, 0.22))
	canvas.draw_circle(center, radius * 0.72, Color(1.0, 0.86, 0.38))
	canvas.draw_arc(center, radius, 0.0, TAU, 24, Color(0.78, 0.55, 0.14), line, true)
	canvas.draw_line(center + Vector2(-radius * 0.25, -radius * 0.45),
			center + Vector2(-radius * 0.25, radius * 0.45), Color(1.0, 0.97, 0.8, 0.9), line * 1.3, true)


## Листик компоста: две дуги и прожилка.
static func draw_leaf(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	var line := maxf(radius * 0.1, 1.5)
	var points := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var along := lerpf(-radius, radius, t)
		points.append(center + Vector2(along, -sin(t * PI) * radius * 0.62).rotated(-0.6))
	for i in range(15, 0, -1):
		var t := float(i) / 16.0
		var along := lerpf(-radius, radius, t)
		points.append(center + Vector2(along, sin(t * PI) * radius * 0.62).rotated(-0.6))
	canvas.draw_colored_polygon(points, Color(0.48, 0.74, 0.3))
	canvas.draw_polyline(points, Color(0.3, 0.52, 0.2), line, true)
	canvas.draw_line(center + Vector2(-radius, 0.0).rotated(-0.6), center + Vector2(radius, 0.0).rotated(-0.6),
			Color(0.32, 0.55, 0.22), line, true)
