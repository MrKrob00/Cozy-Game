class_name EventApples
extends Node3D
## Яблокопад: ближайшая к герою яблоня на виду качнётся от ветра, с неё
## слетают листья и падают яблоки — глухо стукаются о землю, откатываются.
## Подобрать косилкой — по монетке-другой (в нескошенной траве яблоко видно,
## когда траву скосят). Яблоко — своя модель, стук — Kenney Impact Sounds.

const COUNT := 4
const COINS := 3
const SEARCH := 14.0

var _tree: PlotProp
var _field: MowField


## Ищет яблоню рядом с героем на экране и роняет с неё яблоки. false — нет такой.
static func start(host: Node, player: Node3D) -> bool:
	if player == null:
		return false
	var camera := host.get_viewport().get_camera_3d()
	var screen := host.get_viewport().get_visible_rect().size
	var best: PlotProp = null
	var best_distance := SEARCH
	for node in host.get_tree().get_nodes_in_group("grass_shaper"):
		var prop := node as PlotProp
		if prop == null or not prop.is_fruit_tree():
			continue
		var distance := prop.global_position.distance_to(player.global_position)
		if distance >= best_distance:
			continue
		if camera and screen.x > 0.0:
			var on_screen := camera.unproject_position(prop.global_position + Vector3.UP * 1.5) / screen
			if camera.is_position_behind(prop.global_position) or on_screen.x < 0.08 or on_screen.x > 0.92 \
					or on_screen.y < 0.08 or on_screen.y > 0.92:
				continue
		best = prop
		best_distance = distance
	if best == null:
		return false
	var event := EventApples.new()
	event.name = "AppleFall"
	event._tree = best
	var plot := Plot.of(best)
	event._field = plot.field if plot else null
	host.add_child(event)
	return true


func _ready() -> void:
	# Порыв ветра: крона качается, сыплются листья.
	_tree.bumped(Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized())
	var points := _tree.get_apple_drop_points(COUNT)
	for i in points.size():
		get_tree().create_timer(0.25 + i * 0.35).timeout.connect(_drop.bind(points[i]))
	get_tree().create_timer(0.25 + points.size() * 0.35 + 2.0).timeout.connect(queue_free)


func _drop(from: Vector3) -> void:
	if not is_instance_valid(_tree):
		return
	var host := get_parent()
	var apple := Models.place(host, "apple", Vector3.ZERO, 1.35, randf() * TAU, false)
	apple.set_meta("no_bake", true)
	apple.global_position = from
	var ground := _tree.global_position.y
	var out := Vector3(from.x - _tree.global_position.x, 0.0, from.z - _tree.global_position.z)
	out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	var land := Vector3(from.x, ground, from.z)
	var rest := land + out * randf_range(0.4, 0.9)
	var fall := sqrt(maxf(from.y - ground, 0.1) * 2.0 / 9.8)
	var field := _field
	var tween := apple.create_tween()
	tween.tween_property(apple, "global_position", land, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		Sfx.play("thud", -10.0, randf_range(1.1, 1.4), 0.1))
	# Подскок и откат от ствола.
	tween.tween_method(func(t: float) -> void:
		apple.global_position = land.lerp(rest, t) + Vector3.UP * 0.18 * 4.0 * t * (1.0 - t)
		apple.rotation.x = t * 6.0, 0.0, 1.0, 0.45)
	tween.tween_callback(func() -> void:
		apple.queue_free()
		EventGift.spawn(host, "apple", rest, COINS, "", field))
