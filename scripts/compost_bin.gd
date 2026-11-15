class_name CompostBin
extends Interactable
## Компостный ящик: сюда высыпают полный мешок.
## Вокруг ящика светится круг на земле, когда мешок заполнен.

const SIZE := Vector3(1.3, 0.9, 1.1)
const TOSS_CLUMPS := 9

var _ring: GlowRing
var _model: Node3D
var _pile: MeshInstance3D
var _burst: CPUParticles3D


func _ready() -> void:
	# Трава высыпается сама, стоит подъехать к ящику.
	auto_interact = true
	interact_radius = 2.0
	_build_visuals()
	GameState.bag_changed.connect(_on_bag_changed)
	GameState.compost_changed.connect(_update_pile)
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)
	_update_pile(GameState.compost)


func get_prompt() -> String:
	return "Высыпать траву"


func can_interact(_player: Player) -> bool:
	return GameState.bag_fill >= 1.0


func interact(player: Player) -> void:
	var gained := GameState.empty_bag()
	GameState.save_game()
	# Трава комочками летит из мешка в ящик; ящик отзывается, когда она долетела.
	var flight := Juice.toss(get_parent(), player.get_bag_position(), global_position + Vector3.UP * 0.75,
			TOSS_CLUMPS)
	Sfx.buzz(20)
	await get_tree().create_timer(flight * 0.75).timeout
	_burst.restart()
	_burst.emitting = true
	Juice.squash(_model, 0.22)
	Sfx.play("dump")
	if gained > 0:
		GameState.show_reward("compost", gained, global_position + Vector3.UP * 1.2)
		Juice.floating_text(self, global_position + Vector3.UP * 1.6, L.t("+%d компоста") % gained,
				Color(0.8, 1.0, 0.55))


func _on_bag_changed(_fill: float, _capacity: float) -> void:
	var full := GameState.is_bag_full()
	_ring.visible = full
	_ring.set_process(full)


func _update_pile(compost: int) -> void:
	# Куча растёт вместе с накопленным компостом.
	var amount := clampf(compost / 20.0, 0.0, 1.0)
	# По Z ящик уже, чем по X: куча чуть сжата, чтобы не выходить сквозь доски.
	_pile.scale = Vector3(1.0, lerpf(0.3, 1.5, amount), 0.85)


func _build_visuals() -> void:
	_model = Node3D.new()
	add_child(_model)
	# Ящик из досок и куча в нём — свои модели (tools/make_models.py).
	Models.place(_model, "compost_bin", Vector3.ZERO, 1.0)
	_pile = Models.place(_model, "compost_pile", Vector3(0.0, 0.3, 0.0), 1.0)
	_pile.set_meta("no_bake", true)
	_model.add_to_group("shadow_dynamic")

	_ring = GlowRing.create(1.15)
	_ring.name = "GlowRing"
	add_child(_ring)

	_burst = CPUParticles3D.new()
	_burst.position = Vector3(0.0, 1.0, 0.0)
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 0.85
	_burst.amount = 40
	_burst.lifetime = 0.8
	_burst.mesh = Models.mesh("fx_clipping")
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
	shape.position = Vector3(0.0, SIZE.y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
