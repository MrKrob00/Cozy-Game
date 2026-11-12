class_name WildFlowers
extends Node3D
## Куртина полевых цветов. Скосить её можно без штрафа, но если объехать,
## она остаётся в саду, а при завершении участка даёт бонус.

## Уникальный идентификатор для сохранения.
@export var flowers_id := ""
## Радиус куртины: трава в нём не растёт.
@export var radius := 0.55
## Монеты за сохранённую куртину при завершении участка.
@export var bonus_coins := 5

const STEM := Color(0.30, 0.62, 0.30)
const CENTER := Color(1.0, 0.85, 0.3)
const PETALS := [Color(0.95, 0.3, 0.28), Color(0.98, 0.97, 0.94), Color(0.42, 0.55, 0.95)]
const NOTICE_DISTANCE := 3.0

var _alive := true
var _time := 0.0
var _model: Node3D
var _stems: Array[Node3D] = []


func _enter_tree() -> void:
	add_to_group("grass_shaper")
	add_to_group("wild_flowers")


func _ready() -> void:
	_build_visuals()
	if GameState.has_flag(_flag()):
		_alive = false
		_model.visible = false


func _process(delta: float) -> void:
	if not _alive:
		return
	_time += delta
	for i in _stems.size():
		_stems[i].rotation.z = sin(_time * 1.5 + i * 1.1) * 0.1

	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var offset := player.get_blade_position() - global_position
	offset.y = 0.0
	if offset.length() < NOTICE_DISTANCE and not GameState.has_flag("hint_wild_flowers"):
		GameState.set_flag("hint_wild_flowers")
		GameState.toast("Полевые цветы! Объезжайте их — тогда они останутся в саду")
	# Нож задел середину куртины — цветы скошены.
	if player.is_blade_spinning() and offset.length() < radius * 0.5 + player.blade_width * 0.5:
		_cut()


func is_alive() -> bool:
	return _alive


func shape_grass(field: MowField) -> void:
	field.block_circle(global_position, radius)


func _cut() -> void:
	_alive = false
	_model.visible = false
	GameState.set_flag(_flag())
	Juice.sparkle(self, global_position + Vector3.UP * 0.5, Color(1.0, 0.6, 0.6), 22)
	Sfx.play("pop", -4.0, 0.8)
	if not GameState.has_flag("hint_wild_flowers_cut"):
		GameState.set_flag("hint_wild_flowers_cut")
		GameState.toast("Цветы скошены — не страшно. За сохранённые в конце дают монеты")


func _build_visuals() -> void:
	_model = Node3D.new()
	add_child(_model)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(flowers_id)
	var petal: Color = PETALS[rng.randi() % PETALS.size()]
	for i in 7:
		var angle := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var distance := rng.randf_range(0.08, radius * 0.75) if i > 0 else 0.0
		var stem := Node3D.new()
		stem.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		_model.add_child(stem)
		_stems.append(stem)
		# Высокие, чтобы головки торчали над травой.
		var height := rng.randf_range(0.7, 0.95)
		Placeholder.part(stem, Placeholder.cylinder(0.025, height), STEM, Vector3(0.0, height * 0.5, 0.0))
		var head := Placeholder.part(stem, Placeholder.sphere(0.14), petal, Vector3(0.0, height, 0.0))
		head.scale = Vector3(1.0, 0.5, 1.0)
		Placeholder.part(stem, Placeholder.sphere(0.06), CENTER, Vector3(0.0, height + 0.04, 0.0))


func _flag() -> String:
	return "wild_cut_" + flowers_id
