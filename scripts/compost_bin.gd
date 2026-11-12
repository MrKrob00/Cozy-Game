class_name CompostBin
extends Interactable
## Компостный ящик: сюда высыпают полный мешок.
## Над ящиком появляется стрелка, когда мешок заполнен.

const WOOD := Color(0.70, 0.50, 0.32)
const WOOD_DARK := Color(0.56, 0.39, 0.25)
const PILE := Color(0.45, 0.62, 0.25)
const ARROW := Color(1.0, 0.80, 0.25)
const SIZE := Vector3(1.3, 0.9, 1.1)
const ARROW_HEIGHT := 2.3

var _arrow: Node3D
var _model: Node3D
var _pile: MeshInstance3D
var _burst: CPUParticles3D
var _time := 0.0


func _ready() -> void:
	# Трава высыпается сама, стоит подъехать к ящику.
	auto_interact = true
	interact_radius = 2.0
	_build_visuals()
	GameState.bag_changed.connect(_on_bag_changed)
	GameState.compost_changed.connect(_update_pile)
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)
	_update_pile(GameState.compost)


func _process(delta: float) -> void:
	if _arrow.visible:
		_time += delta
		_arrow.position.y = ARROW_HEIGHT + sin(_time * 4.0) * 0.18
		_arrow.rotate_y(delta * 2.0)


func get_prompt() -> String:
	return "Высыпать траву"


func can_interact(_player: Player) -> bool:
	return GameState.bag_fill >= 1.0


func interact(_player: Player) -> void:
	var gained := GameState.empty_bag()
	_burst.restart()
	_burst.emitting = true
	Juice.squash(_model, 0.22)
	Sfx.play("dump")
	Sfx.buzz(20)
	if gained > 0:
		Juice.floating_text(self, global_position + Vector3.UP * 1.6, "+%d компоста" % gained,
				Color(0.8, 1.0, 0.55))
	GameState.save_game()


func _on_bag_changed(_fill: float, _capacity: float) -> void:
	_arrow.visible = GameState.is_bag_full()


func _update_pile(compost: int) -> void:
	# Куча растёт вместе с накопленным компостом.
	var amount := clampf(compost / 20.0, 0.0, 1.0)
	_pile.scale = Vector3(1.0, lerpf(0.3, 1.25, amount), 1.0)


func _build_visuals() -> void:
	var half := SIZE * 0.5
	_model = Node3D.new()
	add_child(_model)
	# Стенки из досок с щелями, верх открыт.
	for side: float in [-1.0, 1.0]:
		for row in 3:
			var y := 0.17 + row * 0.29
			Placeholder.part(_model, Placeholder.box(Vector3(SIZE.x, 0.22, 0.06)), WOOD,
					Vector3(0.0, y, half.z * side))
			Placeholder.part(_model, Placeholder.box(Vector3(0.06, 0.22, SIZE.z)), WOOD,
					Vector3(half.x * side, y, 0.0))
		for z_side: float in [-1.0, 1.0]:
			Placeholder.part(_model, Placeholder.box(Vector3(0.12, SIZE.y + 0.1, 0.12)), WOOD_DARK,
					Vector3(half.x * side, (SIZE.y + 0.1) * 0.5, half.z * z_side))
	_pile = Placeholder.part(_model, Placeholder.sphere(0.52), PILE, Vector3(0.0, 0.25, 0.0))

	_arrow = Node3D.new()
	_arrow.position = Vector3(0.0, ARROW_HEIGHT, 0.0)
	add_child(_arrow)
	Placeholder.part(_arrow, Placeholder.cylinder(0.0, 0.6, 0.4), ARROW, Vector3(0.0, 0.0, 0.0))
	Placeholder.part(_arrow, Placeholder.cylinder(0.15, 0.5), ARROW, Vector3(0.0, 0.52, 0.0))

	_burst = CPUParticles3D.new()
	_burst.position = Vector3(0.0, 1.0, 0.0)
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 0.85
	_burst.amount = 40
	_burst.lifetime = 0.8
	_burst.mesh = Placeholder.box(Vector3(0.06, 0.015, 0.13))
	_burst.material_override = Placeholder.material(Color(0.62, 0.86, 0.34))
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.direction = Vector3.UP
	_burst.spread = 40.0
	_burst.initial_velocity_min = 2.0
	_burst.initial_velocity_max = 4.0
	_burst.angular_velocity_min = -360.0
	_burst.angular_velocity_max = 360.0
	_burst.gravity = Vector3(0.0, -9.0, 0.0)
	add_child(_burst)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position = Vector3(0.0, half.y, 0.0)
	body.add_child(shape)
	add_child(body)
