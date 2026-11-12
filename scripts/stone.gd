class_name Stone
extends Interactable
## Камень в траве. Косилка в него упирается; его убирают контекстной кнопкой.

## Уникальный идентификатор для сохранения.
@export var stone_id := ""
@export var coins_reward := 2

const ROCK := Color(0.62, 0.62, 0.66)
const ROCK_DARK := Color(0.5, 0.5, 0.55)

var _removed := false
var _model: Node3D
var _body: StaticBody3D


func _enter_tree() -> void:
	super()
	add_to_group("grass_shaper")
	add_to_group("stone")


func _ready() -> void:
	interact_radius = 1.5
	auto_interact = true
	_build_visuals()
	if GameState.has_flag(_flag()):
		_removed = true
		_model.visible = false
		_body.process_mode = Node.PROCESS_MODE_DISABLED


func is_removed() -> bool:
	return _removed


func shape_grass(field: MowField) -> void:
	field.pave_circle(global_position, 0.4)


func get_prompt() -> String:
	return "Убрать камень"


func can_interact(_player: Player) -> bool:
	return not _removed


func interact(_player: Player) -> void:
	_removed = true
	GameState.set_flag(_flag())
	GameState.add_coins(coins_reward)
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	Sfx.play("pop", 0.0, 0.7)
	Sfx.play("coin", -6.0)
	Juice.floating_text(self, global_position + Vector3.UP * 0.7, "+%d" % coins_reward, Color(1.0, 0.86, 0.35))
	# Камень подпрыгивает и исчезает.
	var tween := create_tween()
	tween.tween_property(_model, "position:y", 0.7, 0.18).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_model, "scale", Vector3.ONE * 1.2, 0.18)
	tween.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(_model.hide)
	GameState.save_game()


func _build_visuals() -> void:
	_model = Node3D.new()
	add_child(_model)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(stone_id)
	var main := Placeholder.part(_model, Placeholder.sphere(0.3), ROCK, Vector3(0.0, 0.16, 0.0))
	main.scale = Vector3(1.1, 0.7, 0.9)
	main.rotation.y = rng.randf() * TAU
	var side := Placeholder.part(_model, Placeholder.sphere(0.17), ROCK_DARK,
			Vector3(rng.randf_range(0.15, 0.25), 0.1, rng.randf_range(-0.2, 0.2)))
	side.scale = Vector3(1.0, 0.75, 1.0)

	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.32
	cylinder.height = 0.6
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.3, 0.0)
	_body.add_child(shape)
	add_child(_body)


func _flag() -> String:
	return "stone_" + stone_id
