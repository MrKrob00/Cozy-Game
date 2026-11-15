class_name EventCat
extends Node3D
## Кот гонится за бабочкой: оба пробегают мимо героя и скрываются вдали.
## Подъедешь косилкой близко — кот пугается, подпрыгивает и удирает.
## Просто для красоты, без награды.

const SPEED := 2.0
const RUN_AWAY := 5.5
## Ближе этого к ножу косилки кот пугается, метры.
const SCARE_DISTANCE := 1.6
## С какого расстояния от героя начинают и где заканчивают, метры.
const START := 10.0
const FINISH := 14.0
## Насколько в стороне от героя проходит их путь, метры.
const PASS_BY := 2.6
## Кот отстаёт от бабочки, метры.
const BEHIND := 1.5

var _player: Player
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _cat: CharacterModel
var _butterfly: Butterfly
var _travelled := 0.0
var _scared := false
var _flee := Vector3.ZERO
var _flee_time := 0.0
var _pounce := 1.5
var _terrain: Terrain


static func spawn(host: Node, player: Player, direction: Vector3) -> EventCat:
	var event := EventCat.new()
	event.name = "CatChase"
	event._player = player
	var side := direction.cross(Vector3.UP).normalized() * PASS_BY
	var at := player.global_position
	event._from = at - direction * START + side
	event._to = at + direction * FINISH + side
	host.add_child(event)
	return event


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	_cat = CharacterModel.create("res://assets/animals/cat.glb", 0.62)
	_cat.rotation.y = PI
	var holder := Node3D.new()
	holder.name = "Cat"
	add_child(holder)
	holder.add_child(_cat)
	_cat.play("run", 1.0, 0.0)
	_butterfly = Butterfly.new()
	_butterfly.roam_radius = 0.45
	_butterfly.color = [Color(1.0, 0.72, 0.3), Color(0.62, 0.82, 1.0), Color(1.0, 0.6, 0.75)].pick_random()
	add_child(_butterfly)
	_update(0.0)


func is_scared() -> bool:
	return _scared


func _process(delta: float) -> void:
	if _scared:
		_flee_time += delta
		var holder := _cat.get_parent() as Node3D
		holder.global_position += _flee * RUN_AWAY * delta
		holder.global_position.y = _ground(holder.global_position) + maxf(0.0, sin(_flee_time * 9.0)) * 0.12
		_butterfly._home += (_to - _from).normalized() * SPEED * delta + Vector3.UP * delta
		if _flee_time > 3.0:
			queue_free()
		return
	_travelled += SPEED * delta
	_update(delta)
	if _player and (_cat.get_parent() as Node3D).global_position.distance_to(_player.get_blade_position()) \
			< SCARE_DISTANCE:
		_scare()
	if _travelled >= _from.distance_to(_to) + BEHIND:
		queue_free()


func _update(delta: float) -> void:
	var direction := (_to - _from).normalized()
	var butterfly_at := _from + direction * _travelled
	_butterfly._home = butterfly_at + Vector3.UP * _ground(butterfly_at) - Vector3.UP * butterfly_at.y
	var holder := _cat.get_parent() as Node3D
	var cat_at := butterfly_at - direction * BEHIND
	cat_at.y = _ground(cat_at)
	# Время от времени подпрыгивает за бабочкой.
	_pounce -= delta
	# Высокие прыжки: в высокой траве кота видно, только когда он прыгает.
	if _pounce < 0.0:
		_pounce = randf_range(0.7, 1.2)
	if _pounce < 0.45:
		cat_at.y += sin(_pounce / 0.45 * PI) * 0.7
	holder.global_position = cat_at
	holder.rotation.y = atan2(-direction.x, -direction.z)


func _scare() -> void:
	_scared = true
	Sfx.play("squeak", -2.0, 1.25)
	var holder := _cat.get_parent() as Node3D
	var away := holder.global_position - _player.global_position
	away.y = 0.0
	_flee = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	holder.rotation.y = atan2(-_flee.x, -_flee.z)
	_cat.play("run", 1.6, 0.05)
	Juice.dust(get_parent(), holder.global_position, 6)


func _ground(at: Vector3) -> float:
	return _terrain.height_at(Vector2(at.x, at.z)) if _terrain else 0.0
