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
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		camera.nudge(1.0, 0.9)

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
	var text := L.t("Найдено: %s") % L.t(display_name)
	if coins_reward > 0:
		GameState.add_coins(coins_reward, _model.global_position)
		text += L.t(" (+%d монет)") % coins_reward
		Sfx.play("coin")
		Juice.floating_text(self, _model.global_position + Vector3.UP * 0.6, "+%d" % coins_reward,
				Color(1.0, 0.86, 0.35))
	GameState.toast(text)
	GameState.save_game()


func _build_visuals() -> void:
	const COIN_SCALE := 0.5
	_model = Node3D.new()
	_model.position = Vector3(0.0, 0.15, 0.0)
	_model.add_to_group("shadow_dynamic")
	add_child(_model)
	# Ключ и монеты — Kenney Platformer Kit, остальное — свои модели
	# (tools/make_models.py).
	match kind:
		Kind.KEY:
			# В наборе ключ лежит вдоль X; у нас он стоит бородкой вниз.
			var key := Models.place(_model, "key", Vector3(0.12, 0.0, 0.0), 1.1)
			key.rotation.z = PI * 0.5
		Kind.DUCK:
			Models.place(_model, "duck", Vector3.ZERO, 1.0)
		Kind.GLASSES:
			Models.place(_model, "glasses", Vector3.ZERO, 1.0)
		Kind.GNOME:
			Models.place(_model, "gnome", Vector3.ZERO, 1.0)
		Kind.LETTER:
			Models.place(_model, "letter", Vector3(0.0, -0.1, 0.0), 1.2)
		Kind.TEAPOT:
			Models.place(_model, "teapot", Vector3.ZERO, 1.0)
		Kind.COINS:
			# Стопка из трёх монет и одна рядом, на ребре.
			for i in 3:
				var coin := Models.place(_model, "coin", Vector3(0.03 * i - 0.03, -0.06 + 0.075 * i, 0.02 * i - 0.1),
						COIN_SCALE)
				coin.rotation.x = PI * 0.5
			var leaning := Models.place(_model, "coin", Vector3(0.2, -0.1, 0.05), COIN_SCALE, 0.5)
			leaning.rotation.z = -0.35

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
