class_name Animal
extends Interactable
## Зверёк в траве. Косилка в него упирается и навредить не может.
## Игрок переносит зверька — тот прыжками уходит в свой уголок.

@export var animal_id := "hedgehog"
@export var display_name := "ёжика"
## Маркер уголка, куда зверёк уходит.
@export var home_path: NodePath
## С какого расстояния игрок «замечает» зверька.
@export var notice_distance := 2.6

var _moved := false
var _noticed := false
var _busy := false
var _body: StaticBody3D
var _model: Node3D
var _time := 0.0
var _last_hop := -1


func _enter_tree() -> void:
	super()
	add_to_group("animal")


func _ready() -> void:
	_build_visuals()
	if GameState.has_flag(_flag()):
		_moved = true
		_settle_at_home()


func _process(delta: float) -> void:
	# Лёгкое «дыхание».
	_time += delta
	if not _busy:
		_model.scale = Vector3.ONE * (1.0 + sin(_time * 2.5) * 0.03)
	if _moved or _noticed:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_to(global_position) < notice_distance:
		_noticed = true
		Sfx.play("squeak")
		Juice.floating_text(self, global_position + Vector3.UP * 0.9, "!", Color(1.0, 0.9, 0.4))
		GameState.toast("Тут кто-то есть! Косилка его не заденет — подойдите и перенесите")
		_hop_in_place()


func is_moved() -> bool:
	return _moved


func get_prompt() -> String:
	return "Перенести %s" % display_name


func can_interact(_player: Player) -> bool:
	return not _moved and not _busy


func interact(_player: Player) -> void:
	_moved = true
	_busy = true
	GameState.set_flag(_flag())
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	Sfx.play("squeak", 0.0, 1.15)
	Sfx.buzz(20)

	var home := get_node_or_null(home_path) as Node3D
	var from := global_position
	var to := home.global_position if home else from + Vector3(3.0, 0.0, 0.0)
	var distance := from.distance_to(to)
	var hops := maxi(roundi(distance / 1.4), 1)
	look_at(Vector3(to.x, from.y, to.z), Vector3.UP)

	var tween := create_tween()
	tween.tween_method(_travel.bind(from, to, hops), 0.0, 1.0, 0.32 * hops)
	tween.tween_callback(func() -> void:
		_busy = false
		Juice.sparkle(self, global_position + Vector3.UP * 0.4, Color(1.0, 0.75, 0.8))
		GameState.save_game())


func _travel(progress: float, from: Vector3, to: Vector3, hops: int) -> void:
	global_position = from.lerp(to, progress)
	var bounce := absf(sin(progress * PI * hops))
	_model.position.y = bounce * 0.55
	# Приземляясь, зверёк сплющивается, в прыжке вытягивается.
	_model.scale = Vector3(1.0, 1.0, 1.0).lerp(Vector3(1.25, 0.7, 1.25), 1.0 - minf(bounce * 4.0, 1.0))
	var hop := int(progress * hops)
	if hop != _last_hop:
		_last_hop = hop
		Sfx.play("hop", -6.0, 1.0, 0.12)


func _hop_in_place() -> void:
	_busy = true
	var tween := create_tween()
	Sfx.play("hop", -6.0)
	tween.tween_property(_model, "position:y", 0.45, 0.14).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", 0.0, 0.16).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _busy = false)


func _settle_at_home() -> void:
	var home := get_node_or_null(home_path) as Node3D
	if home:
		global_position = home.global_position
	_body.process_mode = Node.PROCESS_MODE_DISABLED


func _flag() -> String:
	return "animal_" + animal_id


# Временная модель ёжика из примитивов (см. Placeholder).
func _build_visuals() -> void:
	const SPIKES := Color(0.45, 0.32, 0.24)
	const FACE := Color(0.93, 0.80, 0.64)
	const DARK := Color(0.15, 0.13, 0.13)

	_model = Node3D.new()
	add_child(_model)
	var back := Placeholder.part(_model, Placeholder.sphere(0.3), SPIKES, Vector3(0.0, 0.24, 0.05))
	back.scale = Vector3(1.0, 0.85, 1.2)
	Placeholder.part(_model, Placeholder.sphere(0.17), FACE, Vector3(0.0, 0.17, -0.3))
	Placeholder.part(_model, Placeholder.sphere(0.045), DARK, Vector3(0.0, 0.17, -0.47))
	for side: float in [-1.0, 1.0]:
		Placeholder.part(_model, Placeholder.sphere(0.03), DARK, Vector3(0.08 * side, 0.24, -0.42))
		Placeholder.part(_model, Placeholder.sphere(0.06), FACE, Vector3(0.14 * side, 0.3, -0.24))
	# Иголки.
	for i in 9:
		var angle := TAU * i / 9.0
		var tilt := 35.0 + 25.0 * (i % 2)
		var spike := Placeholder.part(_model, Placeholder.cylinder(0.05, 0.2, 0.0), SPIKES,
				Vector3(sin(angle) * 0.17, 0.44, 0.07 + cos(angle) * 0.2))
		spike.rotation_degrees = Vector3(cos(angle) * tilt, 0.0, -sin(angle) * tilt)

	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.38
	cylinder.height = 0.7
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.35, 0.0)
	_body.add_child(shape)
	add_child(_body)
