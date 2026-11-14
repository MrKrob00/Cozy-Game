class_name Villager
extends Node3D
## Житель деревни. Появляется, когда выкошен его участок, и говорит
## короткие реплики, когда игрок подходит.

enum Look { MASTER, GRANDMA, POSTMAN }

@export var look := Look.MASTER
@export var display_name := "Мастер"
## Участок, после покоса которого житель возвращается (пусто — он на месте сразу).
@export var appears_after_plot := ""
## Сообщение о возвращении жителя.
@export var arrival_text := ""
## Реплики; показываются по очереди при каждом подходе игрока.
@export var lines: PackedStringArray = []
## Если этот флаг ещё не получен, житель говорит needs_flag_line вместо обычных реплик.
@export var needs_flag := ""
@export var needs_flag_line := ""
@export var talk_distance := 3.8
## Куда житель смотрит, когда игрока рядом нет (поворот по Y, градусы).
@export var facing_degrees := -135.0

## Задержка появления после покоса участка (пока идёт облёт камеры), секунд.
const ARRIVAL_DELAY := 7.0
const MODELS := {Look.MASTER: "master", Look.GRANDMA: "grandma", Look.POSTMAN: "postman"}
## Рост жителей, метры.
const HEIGHTS := {Look.MASTER: 1.5, Look.GRANDMA: 1.38, Look.POSTMAN: 1.5}

var _present := false
var _near := false
var _line_index := 0
var _time := 0.0
var _model: Node3D
var _figure: CharacterModel
var _festive := false
var _next_cheer := 0.0
var _bubble: Label3D
var _body: StaticBody3D


func _ready() -> void:
	add_to_group("shadow_dynamic")
	_build_visuals()
	global_rotation.y = deg_to_rad(facing_degrees)
	_present = appears_after_plot == "" or GameState.is_plot_completed(appears_after_plot)
	var village := get_tree().get_first_node_in_group("village") as Village
	if village:
		village.festival_started.connect(func(_announce: bool) -> void: _festive = true)
	visible = _present
	_body.process_mode = Node.PROCESS_MODE_INHERIT if _present else Node.PROCESS_MODE_DISABLED
	if not _present:
		for plot: Plot in get_tree().get_nodes_in_group("plot"):
			if plot.plot_id == appears_after_plot:
				plot.completed.connect(_on_plot_completed)


func _process(delta: float) -> void:
	if not _present:
		return
	_time += delta
	# На празднике жители время от времени подпрыгивают от радости.
	if _festive and _time >= _next_cheer:
		_next_cheer = _time + randf_range(2.0, 4.5)
		_figure.play("jump", 1.0, 0.1)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var near := to_player.length() < talk_distance
	# Поворачивается к игроку, а без него — в исходную сторону.
	var target := atan2(-to_player.x, -to_player.z) if near else deg_to_rad(facing_degrees)
	global_rotation.y = lerp_angle(global_rotation.y, target, 1.0 - exp(-5.0 * delta))
	if near != _near:
		_near = near
		if near:
			_say_next()
		else:
			_bubble.visible = false
			get_tree().call_group("hud", "hide_speech", self)


func is_present() -> bool:
	return _present


func _on_plot_completed() -> void:
	await get_tree().create_timer(ARRIVAL_DELAY).timeout
	_present = true
	visible = true
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	_model.scale = Vector3.ONE * 0.01
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Juice.sparkle(self, global_position + Vector3.UP * 0.8, Color(1.0, 0.9, 0.6), 26)
	Sfx.play("plant", -3.0, 0.8)
	if arrival_text != "":
		GameState.toast(arrival_text)


func _say_next() -> void:
	var text := ""
	if needs_flag != "" and not GameState.has_flag(needs_flag):
		text = needs_flag_line
	elif not lines.is_empty():
		text = lines[_line_index % lines.size()]
		_line_index += 1
	if text == "":
		return
	get_tree().call_group("hud", "show_speech", self, display_name, text)
	_figure.play("emote-yes", 1.0, 0.15)
	_bubble.visible = true
	_bubble.scale = Vector3.ONE * 0.5
	var tween := create_tween()
	tween.tween_property(_bubble, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("pop", -6.0, 0.9)


# Жители — модели Kenney Mini Characters (CC0) со своими анимациями.
func _build_visuals() -> void:
	_model = Node3D.new()
	add_child(_model)
	_figure = CharacterModel.create("res://assets/characters/%s.glb" % MODELS[look], HEIGHTS[look])
	# Модель смотрит на +Z, житель — на −Z.
	_figure.rotation.y = PI
	_model.add_child(_figure)
	_figure.play("idle", 1.0, 0.0)
	if _figure.animation:
		# После жеста — снова стоит спокойно.
		_figure.animation.animation_finished.connect(func(_finished: StringName) -> void: _figure.play("idle"))

	_bubble = Label3D.new()
	# Отметка над головой говорящего; сама реплика показывается в интерфейсе.
	_bubble.text = "…"
	_bubble.position = Vector3(0.0, 2.0, 0.0)
	_bubble.font_size = 96
	_bubble.pixel_size = 0.006
	_bubble.modulate = Color(0.27, 0.22, 0.17)
	_bubble.outline_modulate = Color(1.0, 0.96, 0.86)
	_bubble.outline_size = 30
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)

	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.4
	cylinder.height = 1.6
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.8, 0.0)
	_body.add_child(shape)
	add_child(_body)
