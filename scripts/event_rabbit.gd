class_name EventRabbit
extends Node3D
## Сад бабушки: в высокой траве кролик грызёт морковку — вокруг него
## маленькая объеденная полянка, так его видно; трава шуршит. Подъедешь
## косилкой — кролик удирает,
## а морковка остаётся: подобрать — монеты. Кролик — Kenney Cube Pets,
## морковка — Kenney Food Kit (CC0).

const HEIGHT := 0.5
## Ближе этого к косилке (или к герою) кролик удирает, метры.
const SCARE := 2.0
const RUN_SPEED := 5.0
## Сколько секунд ждёт, потом уходит сам (вместе с морковкой).
const PATIENCE := 120.0
const CARROT_COINS := 8
## Объеденная полянка вокруг кролика, метры.
const CLEARING := 0.9

var field: MowField

var _player: Node3D
var _rabbit: CharacterModel
var _holder: Node3D
var _carrot: MeshInstance3D
var _time := 0.0
var _rustle := 1.5
var _fled := false
var _flee := Vector3.ZERO


static func spawn(host: Node, at: Vector3, grass: MowField) -> EventRabbit:
	var event := EventRabbit.new()
	event.name = "Rabbit"
	event.field = grass
	# Хозяин (PlotEvents) стоит в начале координат: позиция задаётся до
	# добавления, чтобы _ready уже знал, где событие.
	event.position = at
	host.add_child(event)
	return event


func _ready() -> void:
	add_to_group("event_rabbit")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	# Объеденная полянка: кролика видно из травы.
	if field:
		field.mow(global_position, Vector3.FORWARD, CLEARING, CLEARING)
	_holder = Node3D.new()
	add_child(_holder)
	_rabbit = CharacterModel.create("res://assets/animals/bunny.glb", HEIGHT)
	_rabbit.rotation.y = PI
	_holder.add_child(_rabbit)
	_rabbit.play("eat", 1.0, 0.0)
	_holder.rotation.y = randf() * TAU
	# Морковка лежит перед кроликом, чуть наискосок.
	_carrot = Models.place(self, "carrot", Vector3.ZERO, 0.42, 0.0, false)
	_carrot.set_meta("no_bake", true)
	_carrot.position = _holder.global_basis.z * -0.28
	_carrot.rotation = Vector3(0.0, _holder.rotation.y + 0.6, PI * 0.5)
	if not GameState.has_flag("hint_rabbit"):
		GameState.set_flag("hint_rabbit")
		GameState.toast("В траве кто-то хрумкает морковкой… Подъедьте поближе")


func is_fled() -> bool:
	return _fled


func _process(delta: float) -> void:
	_time += delta
	if _fled:
		_holder.global_position += _flee * RUN_SPEED * delta
		_holder.position.y = absf(sin(_time * 14.0)) * 0.18
		if _time > 2.6:
			queue_free()
		return
	# Трава шуршит, когда герой неподалёку: так кролика легче найти.
	_rustle -= delta
	if _rustle <= 0.0 and _player:
		_rustle = randf_range(2.0, 3.5)
		var distance := _player.global_position.distance_to(global_position)
		if distance < 9.0:
			Sfx.play("rustle", -14.0 - distance * 1.2, 1.3, 0.1)
			Juice.glint(get_parent(), global_position + Vector3.UP * 0.7, Color(0.95, 0.75, 0.4))
	var close := false
	if _player:
		var blade: Vector3 = _player.get_blade_position() if _player.has_method("get_blade_position") else _player.global_position
		close = Vector2(blade.x - global_position.x, blade.z - global_position.z).length() < SCARE \
				or Vector2(_player.global_position.x - global_position.x,
						_player.global_position.z - global_position.z).length() < SCARE
	if close:
		_run(true)
	elif _time > PATIENCE:
		_run(false)


# Кролик удирает от героя; морковку бросает (если его спугнули).
func _run(drop_carrot: bool) -> void:
	_fled = true
	_time = 0.0
	Sfx.play("squeak", -6.0, 1.5)
	var away := global_position - (_player.global_position if _player else global_position + Vector3.FORWARD)
	away.y = 0.0
	_flee = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	_holder.rotation.y = atan2(-_flee.x, -_flee.z)
	_rabbit.play("run", 1.6, 0.05)
	Juice.dust(get_parent(), global_position, 5)
	if drop_carrot:
		var at := _carrot.global_position
		_carrot.queue_free()
		EventGift.spawn(get_parent(), "carrot", Vector3(at.x, global_position.y, at.z), CARROT_COINS,
				"", field)
	else:
		_carrot.reparent(_holder)
