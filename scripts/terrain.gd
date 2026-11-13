class_name Terrain
extends Node
## Карта деревни: дороги и высота земли в любой точке.
##
## Деревня — «звезда»: в середине поляна с дубом, от неё к каждому участку
## идёт своя короткая дорога. С поляны видны все четыре калитки, от любой
## калитки до следующей — не больше трёх десятков шагов, заблудиться негде:
##
##                     [Двор, 0 м]
##                          │
##   [Сад бабушки, 2 м] ─ ПОЛЯНА, 1 м ─ [Фруктовый сад, 3 м]
##                          │
##                    [Площадь, 1,6 м]
##
## Участки открываются по кругу против часовой стрелки: двор → сад бабушки →
## площадь → фруктовый сад. Каждый стоит на своей террасе: от двора вся
## деревня поднимается к фруктовому саду, за ним на холме — мельница.
##
## Участки стоят на ровных террасах (высота — y узла участка), дороги — по
## профилям высоты, между ними земля плавно переходит от одного к другому,
## вдали — холмы. Игрок, земля, дорога и россыпи берут высоту отсюда.

## Ширина дороги, по которой ходит игрок, метры.
const WIDTH := 3.8
## Середина поляны (x, z) и её высота.
const GREEN_CENTER := Vector2(0.0, 26.0)
const GREEN_LEVEL := 1.0

## Дороги начинаются в 0,9 м за калиткой: сам проход — у участка (PlotFence).
## Где ходит игрок вне участков: прямоугольник (мировые X, Z), ось («x» или
## «z») и профиль высоты вдоль оси — точки [координата, высота]; между
## точками плавный подъём. Там, где области сходятся, профили совпадают.
## «green» — не дорога, а вытоптанная трава поляны (грунт на ней не рисуется).
var roads: Array[Dictionary] = [
	{"name": "green", "rect": Rect2(-8.0, 19.0, 16.0, 14.0), "axis": "x", "green": true,
		"profile": [Vector2(-8.0, GREEN_LEVEL), Vector2(8.0, GREEN_LEVEL)]},
	{"name": "yard", "rect": Rect2(-WIDTH * 0.5, 9.4, WIDTH, 9.8), "axis": "z",
		"profile": [Vector2(9.4, 0.0), Vector2(11.5, 0.0), Vector2(17.0, GREEN_LEVEL), Vector2(19.2, GREEN_LEVEL)]},
	{"name": "garden", "rect": Rect2(-16.1, 26.0 - WIDTH * 0.5, 8.3, WIDTH), "axis": "x",
		"profile": [Vector2(-16.1, 2.0), Vector2(-15.0, 2.0), Vector2(-10.0, GREEN_LEVEL), Vector2(-7.8, GREEN_LEVEL)]},
	{"name": "square", "rect": Rect2(-WIDTH * 0.5, 32.8, WIDTH, 7.3), "axis": "z",
		"profile": [Vector2(32.8, GREEN_LEVEL), Vector2(35.0, GREEN_LEVEL), Vector2(39.0, 1.6), Vector2(40.1, 1.6)]},
	{"name": "orchard", "rect": Rect2(7.8, 26.0 - WIDTH * 0.5, 11.3, WIDTH), "axis": "x",
		"profile": [Vector2(7.8, GREEN_LEVEL), Vector2(9.5, GREEN_LEVEL), Vector2(17.4, 3.0), Vector2(19.1, 3.0)]},
]

## Грунт на поляне: дороги сходятся крестом к утоптанному кругу в середине.
var dirt_rects: Array[Rect2] = [
	Rect2(-WIDTH * 0.5, 19.0, WIDTH, 14.0),
	Rect2(-8.0, 26.0 - WIDTH * 0.5, 16.0, WIDTH),
]
## Утоптанные круги: [центр (x, z), радиус].
var dirt_spots: Array = [[GREEN_CENTER, 3.7]]

## Ровные круглые площадки вне дорог: [центр (x, z), радиус, высота].
## Пруд у поляны и холм с мельницей.
var flats: Array = [
	[Vector2(12.0, 36.0), 3.6, 1.3],
	[Vector2(-27.0, -9.0), 5.0, 5.5],
]

## Высота холмов вдали от деревни и уровень земли за краем карты.
@export var hill_height := 2.4
@export var far_level := -0.2
@export var random_seed := 17

var _plots: Array[Plot] = []
var _hills: FastNoiseLite


static func of(node: Node) -> Terrain:
	return node.get_tree().get_first_node_in_group("terrain") as Terrain


func _enter_tree() -> void:
	add_to_group("terrain")
	_hills = FastNoiseLite.new()
	_hills.seed = random_seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.035


## Прямоугольники дорог, по которым ходит игрок.
func road_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for road in roads:
		rects.append(road["rect"])
	return rects


## Насколько точка внутри нарисованного грунта (дороги, крест и круг на
## поляне), метры; отрицательное — снаружи. margin расширяет грунт.
func dirt_depth(at: Vector2, margin := 0.0) -> float:
	var depth := -INF
	for road in roads:
		if not road.get("green", false):
			depth = maxf(depth, _rect_depth(road["rect"], at, margin))
	for rect in dirt_rects:
		depth = maxf(depth, _rect_depth(rect, at, margin))
	for spot: Array in dirt_spots:
		depth = maxf(depth, spot[1] + margin - at.distance_to(spot[0]))
	return depth


## Высота дороги в точке (точка должна лежать на дороге или рядом с ней).
func road_height(road: Dictionary, at: Vector2) -> float:
	var along := at.x if road["axis"] == "x" else at.y
	var points: Array = road["profile"]
	if along <= points[0].x:
		return points[0].y
	for i in range(1, points.size()):
		if along <= points[i].x:
			var t := inverse_lerp(points[i - 1].x, points[i].x, along)
			return lerpf(points[i - 1].y, points[i].y, smoothstep(0.0, 1.0, t))
	return points[-1].y


## Насколько точка внутри дороги: расстояние до её края, метры
## (отрицательное — снаружи). margin расширяет дороги.
func road_depth(at: Vector2, margin := 0.0) -> float:
	var depth := -INF
	for road in roads:
		depth = maxf(depth, _rect_depth(road["rect"], at, margin))
	return depth


func _rect_depth(area: Rect2, at: Vector2, margin: float) -> float:
	var rect := area.grow(margin)
	var inside := minf(minf(at.x - rect.position.x, rect.end.x - at.x),
			minf(at.y - rect.position.y, rect.end.y - at.y))
	if inside < 0.0:
		inside = -at.distance_to(at.clamp(rect.position, rect.end))
	return inside


## Высота земли в точке (x, z) — для игрока, земли и россыпей.
func height_at(at: Vector2) -> float:
	_cache_plots()
	# Где ходят — ровно по своим правилам: участки, дороги, площадки.
	for plot in _plots:
		if _plot_rect(plot).has_point(at):
			return plot.global_position.y
	for road in roads:
		if (road["rect"] as Rect2).grow(1.0).has_point(at):
			return road_height(road, at)
	for flat: Array in flats:
		if at.distance_to(flat[0]) <= flat[1]:
			return flat[2]

	# Между ними земля плавно перетекает от одного к другому: каждая область
	# тянет высоту к себе тем сильнее, чем она ближе.
	var weight_sum := 0.0
	var height_sum := 0.0
	var nearest := INF
	for plot in _plots:
		var rect := _plot_rect(plot)
		var distance := at.distance_to(at.clamp(rect.position, rect.end))
		var weight := 1.0 / (distance * distance + 0.01)
		weight_sum += weight
		height_sum += weight * plot.global_position.y
		nearest = minf(nearest, distance)
	for road in roads:
		var rect: Rect2 = (road["rect"] as Rect2).grow(1.0)
		var closest := at.clamp(rect.position, rect.end)
		var distance := at.distance_to(closest)
		var weight := 1.0 / (distance * distance + 0.01)
		weight_sum += weight
		height_sum += weight * road_height(road, closest)
		nearest = minf(nearest, distance)
	for flat: Array in flats:
		var distance := maxf(at.distance_to(flat[0]) - flat[1], 0.0)
		var weight := 1.0 / (distance * distance + 0.01)
		weight_sum += weight
		height_sum += weight * flat[2]
		nearest = minf(nearest, distance)
	var height := height_sum / weight_sum

	# Вдали от деревни — холмы; у края карты земля выходит на общий уровень.
	var hills := (0.5 + 0.5 * _hills.get_noise_2dv(at)) * hill_height
	height += hills * smoothstep(5.0, 14.0, nearest) * (1.0 - smoothstep(19.0, 26.0, nearest))
	return lerpf(height, far_level, smoothstep(16.0, 27.0, nearest))


## Наклон земли в точке: нормаль (для освещения склонов).
func normal_at(at: Vector2) -> Vector3:
	const STEP := 0.6
	var dx := height_at(at + Vector2(STEP, 0.0)) - height_at(at - Vector2(STEP, 0.0))
	var dz := height_at(at + Vector2(0.0, STEP)) - height_at(at - Vector2(0.0, STEP))
	return Vector3(-dx, 2.0 * STEP, -dz).normalized()


## Прямоугольник, в котором лежат все дороги и участки.
func bounds() -> Rect2:
	_cache_plots()
	var area: Rect2 = roads[0]["rect"]
	for road in roads:
		area = area.merge(road["rect"])
	for plot in _plots:
		area = area.merge(_plot_rect(plot))
	for flat: Array in flats:
		area = area.merge(Rect2(flat[0] - Vector2.ONE * flat[1], Vector2.ONE * flat[1] * 2.0))
	return area


func _plot_rect(plot: Plot) -> Rect2:
	var offset := plot.fence.fence_offset if plot.fence else 2.0
	return plot.get_inner_rect().grow(offset - Plot.WALK_MARGIN + 0.8)


func _cache_plots() -> void:
	if _plots.is_empty():
		for node in get_tree().get_nodes_in_group("plot"):
			_plots.append(node as Plot)
