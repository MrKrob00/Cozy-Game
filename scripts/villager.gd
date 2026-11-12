class_name Villager
extends Node3D
## Житель деревни. Появляется, когда выкошен его участок, и говорит
## короткие реплики, когда игрок подходит.

enum Look { MASTER, GRANDMA }

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
const HAND := Vector3(0.27, 0.6, -0.12)

var _present := false
var _near := false
var _line_index := 0
var _time := 0.0
var _model: Node3D
var _bubble: Label3D
var _body: StaticBody3D


func _ready() -> void:
	_build_visuals()
	rotation_degrees.y = facing_degrees
	_present = appears_after_plot == "" or GameState.is_plot_completed(appears_after_plot)
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
	_model.position.y = absf(sin(_time * 2.2)) * 0.025
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var near := to_player.length() < talk_distance
	# Поворачивается к игроку, а без него — в исходную сторону.
	var target := atan2(-to_player.x, -to_player.z) if near else deg_to_rad(facing_degrees)
	rotation.y = lerp_angle(rotation.y, target, 1.0 - exp(-5.0 * delta))
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
	_bubble.visible = true
	_bubble.scale = Vector3.ONE * 0.5
	var tween := create_tween()
	tween.tween_property(_bubble, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("pop", -6.0, 0.9)


# Временные модели из примитивов (см. Placeholder).
func _build_visuals() -> void:
	const SKIN := Color(1.0, 0.82, 0.66)
	const DARK := Color(0.25, 0.22, 0.24)
	match look:
		Look.MASTER:
			_model = Placeholder.person(self, Color(0.56, 0.42, 0.30), Color(0.86, 0.34, 0.28), SKIN, HAND)
			# Кепка с козырьком и усы.
			Placeholder.part(_model, Placeholder.cylinder(0.27, 0.12, 0.24), DARK, Vector3(0.0, 1.36, 0.0))
			Placeholder.part(_model, Placeholder.box(Vector3(0.36, 0.04, 0.2)), DARK, Vector3(0.0, 1.32, -0.3))
			Placeholder.part(_model, Placeholder.box(Vector3(0.24, 0.05, 0.05)), Color(0.4, 0.3, 0.24), Vector3(0.0, 1.05, -0.27))
		Look.GRANDMA:
			_model = Placeholder.person(self, Color(0.62, 0.48, 0.76), Color(0.97, 0.92, 0.84), SKIN, HAND)
			# Седые волосы с пучком и платок на плечах.
			const HAIR := Color(0.88, 0.88, 0.9)
			var hair := Placeholder.part(_model, Placeholder.sphere(0.29), HAIR, Vector3(0.0, 1.17, 0.05))
			hair.scale = Vector3(1.0, 0.9, 1.0)
			Placeholder.part(_model, Placeholder.sphere(0.13), HAIR, Vector3(0.0, 1.42, 0.12))
			Placeholder.part(_model, Placeholder.cylinder(0.3, 0.12, 0.22), Color(0.95, 0.6, 0.65), Vector3(0.0, 0.84, 0.0))
	_model.scale = Vector3.ONE * 1.1

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
