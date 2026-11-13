class_name Terrain
extends Node
## Карта деревни: сеть дорог и высота земли в любой точке.
##
## Деревня — не улица, а кольцо вокруг центральной поляны:
##
##                    [Двор, 0 м]
##        ┌──────── северная дорога ────────┐
##        │                                 │
##   [Сад │   поляна: площадка у дуба,      │ спуск ── [Фруктовый
##  бабушки,  пруд, тропа напрямик          │ домой     сад, 4,5 м]
##   1,5 м]                                 │
##        └───────── южная дорога ──────────┘
##                  [Площадь, 3 м]
##
## Дорога поднимается по кругу от двора к фруктовому саду и оттуда крутым
## спуском возвращается домой. Тропа через поляну — короткий путь.
##
## Участки стоят на ровных террасах (высота — y узла участка), дороги — по
## профилям высоты, между ними земля плавно переходит от одного к другому,
## вдали — холмы. Игрок, земля, дорога и россыпи берут высоту отсюда.

## Ширина дороги, по которой ходит игрок, метры.
const WIDTH := 3.8

## Дороги: прямоугольник (мировые X, Z), ось («x» или «z») и профиль высоты
## вдоль оси — точки [координата, высота]; между точками плавный подъём.
## На перекрёстках профили совпадают.
var roads: Array[Dictionary] = [
	{"name": "north", "rect": Rect2(-46.0, 9.4, 60.0, WIDTH), "axis": "x",
		"profile": [Vector2(-46.0, 1.5), Vector2(-40.0, 1.5), Vector2(-22.0, 0.0), Vector2(14.0, 0.0)]},
	{"name": "west", "rect": Rect2(-46.0, 9.4, WIDTH, 40.4), "axis": "z",
		"profile": [Vector2(9.4, 1.5), Vector2(36.0, 1.5), Vector2(45.0, 3.0), Vector2(49.8, 3.0)]},
	{"name": "south", "rect": Rect2(-46.0, 46.0, 60.0, WIDTH), "axis": "x",
		"profile": [Vector2(-46.0, 3.0), Vector2(-1.0, 3.0), Vector2(9.0, 4.5), Vector2(14.0, 4.5)]},
	{"name": "east", "rect": Rect2(10.2, 9.4, WIDTH, 40.4), "axis": "z",
		"profile": [Vector2(9.4, 0.0), Vector2(13.4, 0.0), Vector2(31.0, 4.5), Vector2(49.8, 4.5)]},
	# Короткий подъезд от восточной дороги к калитке фруктового сада: сад стоит
	# в стороне от спуска, иначе его терраса обрывалась бы прямо в дорогу.
	{"name": "spur", "rect": Rect2(13.0, 32.1, 9.1, WIDTH), "axis": "x",
		"profile": [Vector2(13.0, 4.5), Vector2(22.1, 4.5)]},
	# Тропа через поляну и площадка у дуба.
	{"name": "path", "rect": Rect2(-17.9, 11.0, WIDTH, 37.0), "axis": "z",
		"profile": [Vector2(11.0, 0.0), Vector2(16.0, 0.0), Vector2(26.0, 1.5), Vector2(33.0, 1.5),
			Vector2(43.0, 3.0), Vector2(48.0, 3.0)]},
	{"name": "glade", "rect": Rect2(-25.0, 26.0, 16.0, 7.0), "axis": "z",
		"profile": [Vector2(26.0, 1.5), Vector2(33.0, 1.5)]},
]

## Ровные круглые площадки вне дорог: [центр (x, z), радиус, высота].
## Пруд на поляне и холм с мельницей.
var flats: Array = [
	[Vector2(-3.0, 30.0), 4.6, 1.2],
	[Vector2(-58.0, -6.0), 5.0, 6.0],
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
		var rect: Rect2 = (road["rect"] as Rect2).grow(margin)
		var inside := minf(minf(at.x - rect.position.x, rect.end.x - at.x),
				minf(at.y - rect.position.y, rect.end.y - at.y))
		if inside < 0.0:
			inside = -at.distance_to(at.clamp(rect.position, rect.end))
		depth = maxf(depth, inside)
	return depth


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
