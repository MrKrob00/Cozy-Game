class_name EventBirds
extends Node3D
## Стая птиц клином пролетает над героем. Просто для красоты.

const COUNT := 7
const SPEED := 6.5
const HEIGHT := 4.5
## Откуда и докуда летят, метры от героя.
const REACH := 18.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _travelled := 0.0
var _time := 0.0
var _birds: Array[Node3D] = []
var _wings: Array[Node3D] = []


static func spawn(host: Node, near: Vector3, direction: Vector3) -> EventBirds:
	var flock := EventBirds.new()
	flock.name = "Birds"
	var over := near + Vector3.UP * HEIGHT
	flock._from = over - direction * REACH
	flock._to = over + direction * REACH
	host.add_child(flock)
	return flock


func _ready() -> void:
	var direction := (_to - _from).normalized()
	rotation.y = atan2(-direction.x, -direction.z)
	for i in COUNT:
		# Клин: ведущий впереди, остальные — уступами по бокам.
		var row := (i + 1) / 2
		var side := 0.0 if i == 0 else (1.0 if i % 2 == 1 else -1.0)
		var bird := Node3D.new()
		bird.position = Vector3(side * row * 0.75, sin(i * 1.3) * 0.15, row * 0.8)
		add_child(bird)
		Models.place(bird, "bird_body", Vector3.ZERO, 1.6, 0.0, false).set_meta("no_bake", true)
		for wing_side: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wing_side * 0.07, 0.03, 0.0)
			bird.add_child(pivot)
			var wing := Models.place(pivot, "bird_wing", Vector3.ZERO, 1.6, 0.0, false)
			wing.scale = Vector3(wing_side * 1.6, 1.6, 1.6)
			wing.set_meta("no_bake", true)
			_wings.append(pivot)
		_birds.append(bird)
	global_position = _from
	Sfx.play("chirp_%d" % randi_range(1, 3), -12.0)


func _process(delta: float) -> void:
	_time += delta
	_travelled += SPEED * delta
	var length := _from.distance_to(_to)
	global_position = _from.lerp(_to, _travelled / length)
	for i in _wings.size():
		var flap := sin(_time * 11.0 + (i / 2) * 0.7) * 0.7
		_wings[i].rotation.z = flap if i % 2 == 1 else -flap
	if _travelled >= length:
		queue_free()
