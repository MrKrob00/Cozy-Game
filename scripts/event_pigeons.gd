class_name EventPigeons
extends Node3D
## Площадь: прилетает стайка сизых голубей и клюёт на выкошенном газоне;
## подъедешь — с хлопаньем крыльев взлетают и улетают. Через минуту улетают
## сами. Просто красота. Голубь — попугай Kenney Cube Pets, перекрашенный в
## сизый (CharacterModel.recolor); взмахи крыльев — запись с OpenGameArt.

const COUNT := 6
## Крупнее настоящих: сверху мелкие сизые птицы сливались с камнями.
const HEIGHT := 0.46
const SCARE := 2.0
const LIFE := 60.0
const FLY_IN := 1.6

var _plot: Plot
var _player: Node3D
var _birds: Array[Dictionary] = []
var _time := 0.0
var _leaving := false


static func spawn(host: Node, plot: Plot, player: Node3D) -> EventPigeons:
	var flock := EventPigeons.new()
	flock.name = "Pigeons"
	flock._plot = plot
	flock._player = player
	host.add_child(flock)
	return flock


func _ready() -> void:
	var spots := _landing_spots()
	var from_direction := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	for spot in spots:
		var holder := Node3D.new()
		add_child(holder)
		var model := CharacterModel.create("res://assets/animals/parrot.glb", HEIGHT)
		model.rotation.y = PI
		model.recolor(Color(0.86, 0.9, 1.0), 0.3)
		holder.add_child(model)
		model.play("idle", 1.0, 0.0)
		var start: Vector3 = spot - from_direction * 9.0 + Vector3.UP * 5.0
		holder.global_position = start
		_birds.append({"node": holder, "model": model, "spot": spot, "start": start, "peck": randf() * 2.0,
				"flee": Vector3.ZERO})
	Sfx.play("flap", -10.0, 1.5)


# Где сесть: выкошенный газон на участке рядом с героем (на виду), иначе
# любое место участка рядом.
func _landing_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var center := _player.global_position if _player else _plot.global_position
	for attempt in 80:
		if spots.size() >= COUNT:
			break
		var angle := randf() * TAU
		var at := center + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(3.2, 6.0)
		at = _plot.field.clamp_to_bounds(at, -0.5)
		at.y = _plot.global_position.y
		var open := _plot.field.is_open_lawn(at)
		if (open or attempt > 50) and spots.all(func(other: Vector3) -> bool: return other.distance_to(at) > 0.6):
			spots.append(at)
	return spots


func _process(delta: float) -> void:
	_time += delta
	var scared := false
	for bird in _birds:
		var node: Node3D = bird["node"]
		if _player and node.global_position.distance_to(_player.global_position) < SCARE and _time > FLY_IN:
			scared = true
	if (scared or _time > LIFE) and not _leaving:
		_take_off()
	for bird in _birds:
		var node: Node3D = bird["node"]
		var model: CharacterModel = bird["model"]
		if _leaving:
			node.global_position += bird["flee"] * delta
			bird["flee"] += Vector3.UP * delta * 2.0
			node.rotation.y = atan2(-bird["flee"].x, -bird["flee"].z)
			continue
		if _time < FLY_IN:
			# Слетаются по дуге и садятся.
			var t := _time / FLY_IN
			node.global_position = (bird["start"] as Vector3).lerp(bird["spot"], 1.0 - pow(1.0 - t, 2.0))
			var heading: Vector3 = bird["spot"] - bird["start"]
			node.rotation.y = atan2(-heading.x, -heading.z)
			continue
		# Клюют: по очереди наклоняются и переступают.
		bird["peck"] -= delta
		if bird["peck"] <= 0.0:
			bird["peck"] = randf_range(1.2, 2.8)
			if randf() < 0.5:
				model.play("eat", 1.2, 0.1)
			else:
				model.play("walk", 1.0, 0.1)
				node.rotation.y += randf_range(-1.2, 1.2)
		if model.animation and model.animation.current_animation == "walk":
			node.global_position += -node.global_basis.z * 0.25 * delta
			node.global_position.y = _plot.global_position.y


func _take_off() -> void:
	_leaving = true
	Sfx.play("flap", -4.0, 1.4)
	var away := Vector3.FORWARD
	if _player:
		away = (global_position_of_flock() - _player.global_position)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	for bird in _birds:
		bird["flee"] = (away + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))).normalized() * 4.5 \
				+ Vector3.UP * 3.0
		(bird["model"] as CharacterModel).play("idle", 2.0, 0.05)
	get_tree().create_timer(4.0).timeout.connect(queue_free)


func global_position_of_flock() -> Vector3:
	var sum := Vector3.ZERO
	for bird in _birds:
		sum += (bird["node"] as Node3D).global_position
	return sum / maxf(_birds.size(), 1.0)
