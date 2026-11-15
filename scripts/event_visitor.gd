class_name EventVisitor
extends Node3D
## Фруктовый сад: знакомый житель (Бабушка, Мастер или Почтальон — кто уже
## вернулся в деревню) приходит через калитку, садится на лавочку, говорит
## реплику, сидит полминуты и уходит той же дорогой — пешком, без телепорта.
## Модель — Kenney Mini Characters (CC0), анимации ходьбы и сидения.

const WALK_SPEED := 1.2
const SIT_TIME := 30.0
## Откуда приходит: столько метров за калиткой.
const OUTSIDE := 3.0
const LINES := {
	Villager.Look.MASTER: "Хорошо тут, яблоками пахнет. Посижу минутку.",
	Villager.Look.GRANDMA: "Ох, ноги уже не те. Посижу, посмотрю, как ты косишь.",
	Villager.Look.POSTMAN: "Пять минут без писем… Красота!",
}

var _look := Villager.Look.MASTER
var _name := ""
var _figure: CharacterModel
var _path: Array[Vector3] = []
## Дорога от калитки (снаружи → внутри); обратно — в обратном порядке.
var _route: Array[Vector3] = []
var _bench: Node3D
var _state := "in"
var _timer := 0.0
var _talked := false
var _stand := Vector3.ZERO
var _terrain: Terrain


static func start(host: Node, orchard: Node) -> bool:
	if orchard == null:
		return false
	var bench := orchard.get_node_or_null("Bench") as Node3D
	var plot := orchard as Plot
	if bench == null or plot == null or plot.fence == null:
		return false
	var everyone := orchard.get_parent().find_children("*", "Villager", true, false)
	var present: Array[Villager] = []
	for node in everyone:
		if (node as Villager).is_present():
			present.append(node)
	if present.is_empty():
		for node in everyone:
			present.append(node)
	if present.is_empty():
		return false
	var who: Villager = present.pick_random()
	var visitor := EventVisitor.new()
	visitor.name = "Visitor"
	visitor._look = who.look
	visitor._name = who.display_name
	visitor._bench = bench
	var gate := plot.fence.get_gate_position()
	var outward := plot.fence.global_basis.z.normalized()
	var seat := bench.global_position + bench.global_basis.z * 0.55
	visitor._route = [gate + outward * OUTSIDE, gate - outward * 0.8]
	visitor._path = [visitor._route[0], visitor._route[1], seat]
	host.add_child(visitor)
	return true


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	_figure = CharacterModel.create("res://assets/characters/%s.glb" % Villager.MODELS[_look], Villager.HEIGHTS[_look])
	_figure.rotation.y = PI
	add_child(_figure)
	_figure.play("walk", 1.0, 0.0)
	global_position = _ground(_path[0])


func _process(delta: float) -> void:
	match _state:
		"in", "out":
			_walk(delta)
		"sit":
			_timer += delta
			if _timer > 1.5 and not _talked:
				_talked = true
				get_tree().call_group("hud", "show_speech", self, _name, LINES[_look])
				get_tree().create_timer(6.0).timeout.connect(func() -> void:
					get_tree().call_group("hud", "hide_speech", self))
			if _timer > SIT_TIME:
				# Встаёт и идёт обратно той же дорогой.
				_state = "out"
				_path = [_stand, _route[1], _route[0]]
				_figure.play("walk", 1.0, 0.2)


func _walk(delta: float) -> void:
	if _path.is_empty():
		return
	var target := _ground(_path[0])
	var to := target - global_position
	to.y = 0.0
	var step := WALK_SPEED * delta
	if to.length() <= step:
		global_position = target
		_path.pop_front()
		if _path.is_empty():
			_arrive()
		return
	global_position += to.normalized() * step
	global_position.y = _ground(global_position).y
	rotation.y = atan2(-to.x, -to.z)


func _arrive() -> void:
	if _state == "in":
		# Садится на лавочку лицом от неё.
		_state = "sit"
		_timer = 0.0
		var facing := _bench.global_basis.z
		rotation.y = atan2(-facing.x, -facing.z)
		global_position = _bench.global_position + facing * 0.05
		_figure.play("sit", 1.0, 0.2)
		_stand = global_position + facing * 0.55
		return
	queue_free()


func _ground(at: Vector3) -> Vector3:
	var y := _terrain.height_at(Vector2(at.x, at.z)) if _terrain else at.y
	return Vector3(at.x, y, at.z)
