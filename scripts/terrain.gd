class_name Terrain
extends Node
## Рельеф деревни: высота земли в любой точке.
##
## Участки стоят на террасах (высота — y узла участка), улица поднимается
## пологими подъёмами между ними (профиль street_profile), вокруг — мягкие
## холмы. Ровно там, где ходят (участки и улица), земля ровная; вокруг —
## склоны от террас к лугу. Игрок, земля, дорога и россыпи берут высоту отсюда.

## Улица (мировые X, Z; ширина, длина): по ней ходят между участками.
## Деревня растёт от двора (x = 0) вверх по склону к −X: на экране это путь
## вверх-влево, каждый следующий участок выше предыдущего.
@export var street := Rect2(-100.0, 9.4, 111.0, 3.8)
## Высота улицы по X: точки [x, высота], между ними — плавный подъём.
@export var street_profile: PackedVector2Array = [
	Vector2(-120.0, 5.4), Vector2(-70.0, 5.4), Vector2(-62.0, 3.6), Vector2(-40.0, 3.6),
	Vector2(-34.0, 1.8), Vector2(-14.0, 1.8), Vector2(-8.0, 0.0), Vector2(20.0, 0.0),
]
## Ширина склона от края террасы или улицы до луга, метры.
@export var slope_width := 5.5
## Высота холмов вдали от деревни.
@export var hill_height := 2.6
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
	_hills.frequency = 0.03


## Высота улицы в точке x.
func street_height(x: float) -> float:
	var points := street_profile
	if x <= points[0].x:
		return points[0].y
	for i in range(1, points.size()):
		if x <= points[i].x:
			var t := inverse_lerp(points[i - 1].x, points[i].x, x)
			return lerpf(points[i - 1].y, points[i].y, smoothstep(0.0, 1.0, t))
	return points[-1].y


## Высота земли в точке (x, z) — для игрока, земли и россыпей.
func height_at(at: Vector2) -> float:
	_cache_plots()
	# Где ходят — ровно: участок со своим забором и улица.
	for plot in _plots:
		if _plot_rect(plot).has_point(at):
			return plot.global_position.y
	if street.grow(1.0).has_point(at):
		return street_height(at.x)
	# Вокруг — склоны от террас и улицы вниз к лугу; дальше — холмы.
	var base := _meadow_height(at)
	var height := base
	var nearest := INF
	for plot in _plots:
		var rect := _plot_rect(plot)
		var distance := at.distance_to(at.clamp(rect.position, rect.end))
		nearest = minf(nearest, distance)
		var level := plot.global_position.y
		height = maxf(height, lerpf(level, base, smoothstep(0.0, slope_width, distance)))
	var road := street.grow(1.0)
	var to_road := at.distance_to(at.clamp(road.position, road.end))
	nearest = minf(nearest, to_road)
	var road_level := street_height(clampf(at.x, road.position.x, road.end.x))
	height = maxf(height, lerpf(road_level, base, smoothstep(0.0, slope_width, to_road)))
	return height


## Наклон земли в точке: нормаль (для освещения склонов).
func normal_at(at: Vector2) -> Vector3:
	const STEP := 0.6
	var dx := height_at(at + Vector2(STEP, 0.0)) - height_at(at - Vector2(STEP, 0.0))
	var dz := height_at(at + Vector2(0.0, STEP)) - height_at(at - Vector2(0.0, STEP))
	return Vector3(-dx, 2.0 * STEP, -dz).normalized()


# Луг вдали от деревни: холмы растут с расстоянием от участков и улицы.
func _meadow_height(at: Vector2) -> float:
	var away := INF
	for plot in _plots:
		var rect := _plot_rect(plot)
		away = minf(away, at.distance_to(at.clamp(rect.position, rect.end)))
	var road := street.grow(1.0)
	away = minf(away, at.distance_to(at.clamp(road.position, road.end)))
	var rise := smoothstep(slope_width, slope_width + 18.0, away)
	var local_street := street_height(clampf(at.x, street.position.x, street.end.x))
	return local_street * 0.5 + (0.5 + 0.5 * _hills.get_noise_2dv(at)) * hill_height * rise


func _plot_rect(plot: Plot) -> Rect2:
	var offset := plot.fence.fence_offset if plot.fence else 2.0
	return plot.get_inner_rect().grow(offset - Plot.WALK_MARGIN + 0.8)


func _cache_plots() -> void:
	if _plots.is_empty():
		for node in get_tree().get_nodes_in_group("plot"):
			_plots.append(node as Plot)
