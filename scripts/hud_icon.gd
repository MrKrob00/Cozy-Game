class_name HudIcon
extends Control
## Значок интерфейса, нарисованный фигурами (без символов шрифта: в шрифте
## их может не быть, а на телефоне поиск символа дорог): монета и листик
## компоста (те же, что летят к счётчикам, RewardIcon), мешок, трава, нож,
## мотор. Или кружки уровня (LEVELS).

enum Kind { COIN, COMPOST, BAG, GRASS, BLADE, MOTOR, LEVELS }

const INK := Color(0.27, 0.22, 0.17)
const LEAF := Color(0.42, 0.72, 0.30)
const LEAF_DARK := Color(0.28, 0.54, 0.24)
const CANVAS := Color(0.50, 0.66, 0.40)
const CANVAS_DARK := Color(0.36, 0.50, 0.30)
const STEEL := Color(0.62, 0.65, 0.70)
const STEEL_DARK := Color(0.40, 0.42, 0.48)
const RED := Color(0.86, 0.30, 0.26)

@export var kind := Kind.COIN
## Для LEVELS: сколько всего уровней и сколько уже есть.
@export var levels := 3
@export var level := 1
## Подложка-кружок под значком (в окнах, где значок стоит отдельно).
@export var badge := false


static func make(icon_kind: Kind, side := 40.0) -> HudIcon:
	var icon := HudIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## Кружки уровня: сколько всего и сколько уже куплено.
static func pips(total: int, filled: int, side := 26.0) -> HudIcon:
	var icon := make(Kind.LEVELS, side)
	icon.levels = total
	icon.level = filled
	icon.custom_minimum_size = Vector2(side * total + 6.0 * (total - 1), side)
	return icon


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(s, s) * 0.5
	if badge:
		draw_circle(c, s * 0.5, Color(0.91, 0.84, 0.68))
		s *= 0.72
	match kind:
		Kind.COIN:
			RewardIcon.draw_coin(self, c, s * 0.42)
		Kind.COMPOST:
			RewardIcon.draw_leaf(self, c, s * 0.46)
		Kind.BAG:
			_bag(c, s)
		Kind.GRASS:
			_grass(c, s)
		Kind.BLADE:
			_blade(c, s)
		Kind.MOTOR:
			_motor(c, s)
		Kind.LEVELS:
			_levels()


func _bag(c: Vector2, s: float) -> void:
	# Мешок: пузатый низ, перевязанное горлышко, раструб ткани сверху.
	var body := PackedVector2Array()
	for k in 20:
		var angle := -PI * 0.5 + TAU * k / 20.0
		var squash := 1.0 if sin(angle) > 0.0 else 0.8
		body.append(c + Vector2(cos(angle) * s * 0.4, s * 0.14 + sin(angle) * s * 0.3 * squash))
	draw_colored_polygon(body, CANVAS)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.1, -s * 0.18), c + Vector2(-s * 0.26, -s * 0.44),
			c + Vector2(-s * 0.08, -s * 0.36), c + Vector2(0.0, -s * 0.46), c + Vector2(s * 0.08, -s * 0.36),
			c + Vector2(s * 0.26, -s * 0.44), c + Vector2(s * 0.1, -s * 0.18)]), CANVAS)
	draw_line(c + Vector2(-s * 0.14, -s * 0.19), c + Vector2(s * 0.14, -s * 0.19), CANVAS_DARK, maxf(s * 0.09, 2.0), true)
	draw_line(c + Vector2(s * 0.14, -s * 0.19), c + Vector2(s * 0.24, -s * 0.06), CANVAS_DARK, maxf(s * 0.05, 1.5), true)
	draw_circle(c + Vector2(-s * 0.16, s * 0.04), s * 0.07, Color(1.0, 1.0, 1.0, 0.25))


func _grass(c: Vector2, s: float) -> void:
	# Пучок травы из пяти травинок.
	var ground := c.y + s * 0.4
	for blade: Array in [[-0.28, 0.5, -0.4, LEAF_DARK], [-0.12, 0.78, -0.15, LEAF], [0.04, 0.88, 0.05, LEAF_DARK],
			[0.18, 0.7, 0.25, LEAF], [0.3, 0.48, 0.42, LEAF_DARK]]:
		var x: float = c.x + blade[0] * s
		var tip := Vector2(c.x + blade[2] * s, ground - blade[1] * s)
		draw_colored_polygon(PackedVector2Array([Vector2(x - s * 0.07, ground), Vector2(x + s * 0.07, ground), tip]),
				blade[3])


func _blade(c: Vector2, s: float) -> void:
	# Нож косилки сверху: два широких лезвия с заточкой и ступица.
	for side: float in [-1.0, 1.0]:
		var dir := Vector2(cos(0.45), sin(0.45)) * side
		var across := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([c - across * s * 0.12, c + dir * s * 0.46 - across * s * 0.1,
				c + dir * s * 0.48 + across * s * 0.16, c + across * s * 0.12]), STEEL)
		draw_line(c + dir * s * 0.2 + across * s * 0.13, c + dir * s * 0.47 + across * s * 0.15, Color(0.88, 0.9, 0.94),
				maxf(s * 0.05, 1.5), true)
	draw_circle(c, s * 0.18, STEEL_DARK)
	draw_circle(c, s * 0.08, INK)


func _motor(c: Vector2, s: float) -> void:
	# Мотор: блок, цилиндр с рёбрами, красная крышка.
	draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.06), Vector2(s * 0.8, s * 0.34)), INK)
	draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.34), Vector2(s * 0.44, s * 0.42)), STEEL)
	for k in 3:
		var y := c.y - s * 0.24 + k * s * 0.12
		draw_line(Vector2(c.x - s * 0.3, y), Vector2(c.x + s * 0.3, y), STEEL_DARK, maxf(s * 0.05, 1.5), true)
	draw_rect(Rect2(c + Vector2(-s * 0.16, -s * 0.46), Vector2(s * 0.32, s * 0.12)), RED)


func _levels() -> void:
	var r := size.y * 0.42
	for i in levels:
		var center := Vector2(size.y * 0.5 + i * (size.y + 6.0), size.y * 0.5)
		if i < level:
			draw_circle(center, r, LEAF_DARK)
			draw_circle(center, r * 0.62, LEAF)
		else:
			draw_arc(center, r * 0.85, 0.0, TAU, 20, Color(INK, 0.35), maxf(r * 0.22, 2.0), true)
