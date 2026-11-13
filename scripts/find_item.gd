class_name FindItem
extends Node3D
## Мелкая находка, спрятанная в высокой траве. Когда траву над ней
## скашивают, выскакивает с искрами и сама летит к игроку.

enum Kind { KEY, DUCK, COINS, GLASSES, GNOME, LETTER, TEAPOT }

## Уникальный идентификатор для сохранения.
@export var find_id := ""
@export var display_name := "Находка"
@export var kind := Kind.KEY
## Сколько монет даёт находка сразу.
@export var coins_reward := 0
## Чья это вещь (пусто — ничья). Вещи с владельцем возвращают через «Бюро находок».
@export var owner_name := ""
## Монеты за возврат владельцу.
@export var return_reward := 0
## Что говорит владелец, получив вещь.
@export var thanks := ""
## Радиус высокой травы вокруг, которая прячет находку.
@export var tall_grass_radius := 1.1

var _field: MowField
var _revealed := false
var _model: Node3D
var _sparkles: CPUParticles3D


func _enter_tree() -> void:
	add_to_group("find")
	add_to_group("grass_shaper")


func _ready() -> void:
	var plot := Plot.of(self)
	_field = plot.field if plot else get_tree().get_first_node_in_group("mow_field") as MowField
	_build_visuals()
	_model.visible = false
	if is_collected():
		set_process(false)


func _process(_delta: float) -> void:
	if not _revealed and _field and _field.get_height_at(global_position) == 0.0:
		_reveal()


func is_collected() -> bool:
	return GameState.has_flag("find_" + find_id)


func is_returned() -> bool:
	return GameState.has_flag("returned_" + find_id)


## Можно ли вернуть вещь владельцу прямо сейчас.
func can_return() -> bool:
	return owner_name != "" and is_collected() and not is_returned()


## Возвращает вещь владельцу и выдаёт награду.
func give_back() -> void:
	if not can_return():
		return
	GameState.set_flag("returned_" + find_id)
	GameState.add_coins(return_reward)
	GameState.save_game()


func shape_grass(field: MowField) -> void:
	field.grow_tall_circle(global_position, tall_grass_radius)


func _reveal() -> void:
	_revealed = true
	set_process(false)
	GameState.set_flag("find_" + find_id)
	_model.visible = true
	_model.scale = Vector3.ONE * 0.2
	_sparkles.emitting = true
	Sfx.play("find")
	Sfx.buzz(30)

	# Выпрыгивает из травы, крутится, затем летит к игроку.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_model, "position:y", 1.5, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "scale", Vector3.ONE * 1.6, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "rotation:y", TAU * 2.0, 1.3)
	tween.set_parallel(false)
	tween.tween_interval(0.85)
	tween.tween_method(_fly_to_player.bind(_model.global_position + Vector3.UP * 1.3), 0.0, 1.0, 0.35)
	tween.tween_callback(_collect)


func _fly_to_player(progress: float, from: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var target := player.global_position + Vector3.UP if player else from
	_model.global_position = from.lerp(target, progress)
	_model.scale = Vector3.ONE * lerpf(1.6, 0.2, progress)


func _collect() -> void:
	_model.visible = false
	Sfx.play("pop")
	var text := "Найдено: %s" % display_name
	if coins_reward > 0:
		GameState.add_coins(coins_reward)
		text += " (+%d монет)" % coins_reward
		Sfx.play("coin")
		Juice.floating_text(self, _model.global_position + Vector3.UP * 0.6, "+%d" % coins_reward,
				Color(1.0, 0.86, 0.35))
	GameState.toast(text)
	GameState.save_game()


func _build_visuals() -> void:
	const GOLD := Color(1.0, 0.80, 0.25)
	const DUCK_YELLOW := Color(1.0, 0.86, 0.22)
	const BEAK := Color(0.96, 0.52, 0.18)
	const DARK := Color(0.2, 0.2, 0.24)

	_model = Node3D.new()
	_model.position = Vector3(0.0, 0.15, 0.0)
	_model.add_to_group("shadow_dynamic")
	add_child(_model)
	match kind:
		Kind.KEY:
			Placeholder.part(_model, Placeholder.cylinder(0.11, 0.04), GOLD,
					Vector3(0.0, 0.16, 0.0), Vector3(90.0, 0.0, 0.0))
			Placeholder.part(_model, Placeholder.box(Vector3(0.05, 0.3, 0.04)), GOLD, Vector3(0.0, -0.08, 0.0))
			Placeholder.part(_model, Placeholder.box(Vector3(0.12, 0.05, 0.04)), GOLD, Vector3(0.05, -0.2, 0.0))
			Placeholder.part(_model, Placeholder.box(Vector3(0.09, 0.05, 0.04)), GOLD, Vector3(0.04, -0.1, 0.0))
		Kind.DUCK:
			Placeholder.part(_model, Placeholder.sphere(0.16), DUCK_YELLOW, Vector3(0.0, 0.0, 0.0))
			Placeholder.part(_model, Placeholder.sphere(0.11), DUCK_YELLOW, Vector3(0.0, 0.18, -0.08))
			Placeholder.part(_model, Placeholder.box(Vector3(0.09, 0.03, 0.09)), BEAK, Vector3(0.0, 0.16, -0.2))
			for side: float in [-1.0, 1.0]:
				Placeholder.part(_model, Placeholder.sphere(0.02), DARK, Vector3(0.05 * side, 0.22, -0.16))
		Kind.GLASSES:
			for side: float in [-1.0, 1.0]:
				Placeholder.part(_model, Placeholder.cylinder(0.1, 0.03), Color(0.62, 0.84, 0.94),
						Vector3(0.12 * side, 0.05, 0.0), Vector3(90.0, 0.0, 0.0))
				Placeholder.part(_model, Placeholder.box(Vector3(0.03, 0.03, 0.22)), DARK,
						Vector3(0.22 * side, 0.05, 0.11))
			Placeholder.part(_model, Placeholder.box(Vector3(0.08, 0.03, 0.03)), DARK, Vector3(0.0, 0.07, 0.0))
		Kind.GNOME:
			Placeholder.part(_model, Placeholder.cylinder(0.13, 0.22, 0.1), Color(0.3, 0.5, 0.85), Vector3(0.0, -0.02, 0.0))
			Placeholder.part(_model, Placeholder.sphere(0.11), Color(1.0, 0.82, 0.66), Vector3(0.0, 0.17, 0.0))
			Placeholder.part(_model, Placeholder.sphere(0.09), Color(0.97, 0.97, 0.95), Vector3(0.0, 0.1, -0.07))
			Placeholder.part(_model, Placeholder.cylinder(0.12, 0.26, 0.0), Color(0.9, 0.3, 0.26), Vector3(0.0, 0.36, 0.0))
		Kind.LETTER:
			Placeholder.part(_model, Placeholder.box(Vector3(0.34, 0.02, 0.24)), Color(0.98, 0.95, 0.86), Vector3(0.0, 0.0, 0.0))
			Placeholder.part(_model, Placeholder.box(Vector3(0.07, 0.025, 0.08)), Color(0.86, 0.3, 0.28), Vector3(0.11, 0.005, -0.06))
			Placeholder.part(_model, Placeholder.box(Vector3(0.16, 0.025, 0.02)), DARK, Vector3(-0.05, 0.005, 0.03))
		Kind.TEAPOT:
			const ENAMEL := Color(0.4, 0.62, 0.86)
			Placeholder.part(_model, Placeholder.sphere(0.16), ENAMEL, Vector3(0.0, 0.05, 0.0))
			Placeholder.part(_model, Placeholder.cylinder(0.1, 0.03), ENAMEL, Vector3(0.0, 0.2, 0.0))
			Placeholder.part(_model, Placeholder.sphere(0.035), GOLD, Vector3(0.0, 0.24, 0.0))
			Placeholder.part(_model, Placeholder.cylinder(0.03, 0.18), ENAMEL, Vector3(0.2, 0.09, 0.0), Vector3(0.0, 0.0, -55.0))
			Placeholder.part(_model, Placeholder.cylinder(0.11, 0.03), ENAMEL, Vector3(-0.19, 0.06, 0.0), Vector3(90.0, 0.0, 0.0))
		Kind.COINS:
			for i in 3:
				Placeholder.part(_model, Placeholder.cylinder(0.11, 0.03), GOLD,
						Vector3(0.03 * i, -0.05 + 0.045 * i, 0.02 * i))
			Placeholder.part(_model, Placeholder.cylinder(0.11, 0.03), GOLD,
					Vector3(0.2, 0.02, 0.05), Vector3(0.0, 0.0, 70.0))

	_sparkles = CPUParticles3D.new()
	_sparkles.position = Vector3(0.0, 0.5, 0.0)
	_sparkles.emitting = false
	_sparkles.one_shot = true
	_sparkles.explosiveness = 0.9
	_sparkles.amount = 24
	_sparkles.lifetime = 0.9
	_sparkles.mesh = Placeholder.sphere(0.04)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.95, 0.6)
	_sparkles.material_override = glow
	_sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparkles.direction = Vector3.UP
	_sparkles.spread = 70.0
	_sparkles.initial_velocity_min = 1.5
	_sparkles.initial_velocity_max = 3.5
	_sparkles.gravity = Vector3(0.0, -3.0, 0.0)
	_sparkles.scale_amount_min = 0.5
	_sparkles.scale_amount_max = 1.4
	add_child(_sparkles)
