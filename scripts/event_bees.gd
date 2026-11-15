class_name EventBees
extends Node3D
## Сад бабушки: над клумбами кружат пчёлы (над засаженными — больше) и
## жужжат; подъедешь — разлетаются и через пару секунд возвращаются.
## Через 45 с улетают. Просто красота. Пчела — Kenney Cube Pets (CC0),
## жужжание — запись с OpenGameArt (CREDITS.md).

const LIFE := 45.0
## Крупнее настоящей: сверху иначе не видно.
const HEIGHT := 0.4
## Ближе этого к косилке пчела отлетает, метры.
const SCARE := 1.8
const SCARE_TIME := 2.2

var _player: Node3D
var _bees: Array[Dictionary] = []
var _buzz: LoopSound
var _time := 0.0
var _leaving := false


## Запускает пчёл над клумбами участка. false — клумб нет.
static func start(host: Node, plot: Node) -> bool:
	if plot == null:
		return false
	var beds: Array[Node3D] = []
	for node in plot.get_tree().get_nodes_in_group("flower_bed"):
		if plot.is_ancestor_of(node):
			beds.append(node)
	if beds.is_empty():
		return false
	var bees := EventBees.new()
	bees.name = "Bees"
	host.add_child(bees)
	for bed in beds:
		var count := 4 if (bed as FlowerBed).is_planted() else 2
		for i in count:
			bees._add_bee(bed.global_position)
	return true


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_buzz = LoopSound.create("buzz", -40.0)
	add_child(_buzz)


func _add_bee(center: Vector3) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var model := CharacterModel.create("res://assets/animals/bee.glb", HEIGHT, false)
	model.rotation.y = PI
	holder.add_child(model)
	model.play("idle", 1.4, 0.0)
	holder.global_position = center + Vector3.UP * 3.0
	_bees.append({"node": holder, "center": center, "phase": randf() * TAU, "speed": randf_range(0.8, 1.3),
			"radius": randf_range(0.45, 0.9), "scared": 0.0, "away": Vector3.ZERO})


func _process(delta: float) -> void:
	_time += delta
	if _time > LIFE and not _leaving:
		_leaving = true
		_buzz.fade_out()
	var nearest := INF
	for bee in _bees:
		var node: Node3D = bee["node"]
		var t: float = _time * bee["speed"] + bee["phase"]
		var r: float = bee["radius"]
		# Кружит над клумбой восьмёркой, покачиваясь по высоте; прилетает сверху.
		var target: Vector3 = bee["center"] + Vector3(sin(t) * r, 0.75 + sin(t * 2.3) * 0.18, sin(t * 2.0) * r * 0.6)
		if _time < 1.5:
			target.y += (1.5 - _time) * 2.0
		if _player:
			var distance := node.global_position.distance_to(_player.global_position + Vector3.UP * 0.6)
			nearest = minf(nearest, distance)
			if distance < SCARE and bee["scared"] <= 0.0:
				bee["scared"] = SCARE_TIME
				var away: Vector3 = node.global_position - _player.global_position
				away.y = 0.0
				bee["away"] = away.normalized() * 2.2 + Vector3.UP * 1.4
		if bee["scared"] > 0.0:
			bee["scared"] -= delta
			target += bee["away"] * minf(bee["scared"] / SCARE_TIME * 2.0, 1.0)
		if _leaving:
			target += Vector3.UP * (_time - LIFE) * 4.0
		var before := node.global_position
		node.global_position = before.lerp(target, 1.0 - exp(-4.0 * delta))
		var heading := node.global_position - before
		if Vector2(heading.x, heading.z).length() > 0.001:
			node.rotation.y = atan2(-heading.x, -heading.z)
	# Жужжание тем громче, чем ближе пчёлы к герою.
	if not _leaving:
		_buzz.level_db = clampf(-10.0 - nearest * 2.2, -40.0, -12.0)
	if _leaving and _time > LIFE + 3.0:
		queue_free()
