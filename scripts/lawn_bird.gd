class_name LawnBird
extends Node3D
## Цыплёнок на выкошенном газоне: награда за покос — участок оживает.
## Клюёт травку, перебегает с места на место, а от косилки удирает.
## Модель — Kenney Cube Pets (CC0).

const HEIGHT := 0.34
## Ближе этого расстояния косилка его спугивает, метры.
const SCARE_DISTANCE := 2.3
const WALK_SPEED := 0.9
const RUN_SPEED := 4.2

enum State { PECK, WALK, FLEE }

var _plot: Plot
var _model: CharacterModel
var _state := State.PECK
var _timer := 0.0
var _target := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


## Ставит птицу на участок (в случайное выкошенное место).
static func spawn(plot: Plot, seed_value: int) -> LawnBird:
	var bird := LawnBird.new()
	bird._plot = plot
	bird._rng.seed = seed_value
	plot.add_child(bird)
	return bird


func _ready() -> void:
	_model = CharacterModel.create("res://assets/animals/chick.glb", HEIGHT, false)
	# Модель смотрит на +Z, птица ходит «вперёд» по −Z.
	_model.rotation.y = PI
	add_child(_model)
	var spot: Variant = _free_spot(global_position, 0.0, 99.0)
	if spot == null:
		queue_free()
		return
	global_position = spot
	rotation.y = _rng.randf() * TAU
	_peck()
	# Появляется с прыжком.
	scale = Vector3.ONE * 0.01
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and _state != State.FLEE:
		var away := global_position - player.global_position
		away.y = 0.0
		if away.length() < SCARE_DISTANCE:
			_flee(away.normalized())
	match _state:
		State.PECK:
			_timer -= delta
			if _timer <= 0.0:
				var spot: Variant = _free_spot(global_position, 0.8, 3.0)
				if spot == null:
					_peck()
				else:
					_go(spot, State.WALK)
		State.WALK, State.FLEE:
			var to_target := _target - global_position
			to_target.y = 0.0
			var speed := RUN_SPEED if _state == State.FLEE else WALK_SPEED
			if to_target.length() <= speed * delta:
				global_position = _target
				_peck()
			else:
				global_position += to_target.normalized() * speed * delta
				rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), 1.0 - exp(-12.0 * delta))


func _peck() -> void:
	_state = State.PECK
	_timer = _rng.randf_range(1.5, 4.5)
	_model.play("eat" if _rng.randf() < 0.7 else "idle")


func _go(spot: Vector3, state: State) -> void:
	_state = state
	_target = spot
	_model.play("run" if state == State.FLEE else "walk", 1.6 if state == State.FLEE else 1.0, 0.1)


# Удирает от косилки: в сторону от неё, на выкошенное место.
func _flee(away: Vector3) -> void:
	for attempt in 8:
		var turn := _rng.randf_range(-0.9, 0.9)
		var spot := global_position + away.rotated(Vector3.UP, turn) * _rng.randf_range(3.0, 5.0)
		if _plot.field.is_open_lawn(spot):
			_go(Vector3(spot.x, global_position.y, spot.z), State.FLEE)
			return
	# Бежать некуда (вокруг трава): отскакивает на месте.
	_go(global_position + away * 0.6, State.FLEE)


# Случайное выкошенное место на расстоянии от from; null — не нашлось.
func _free_spot(from: Vector3, nearest: float, farthest: float) -> Variant:
	var half: Vector2 = _plot.field.size * 0.5 - Vector2.ONE * 0.6
	for attempt in 14:
		var spot: Vector3
		if farthest > 50.0:
			spot = _plot.field.to_global(Vector3(_rng.randf_range(-half.x, half.x), 0.0,
					_rng.randf_range(-half.y, half.y)))
		else:
			var angle := _rng.randf() * TAU
			spot = from + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(nearest, farthest)
		if _plot.field.is_open_lawn(spot):
			return Vector3(spot.x, _plot.global_position.y, spot.z)
	return null
