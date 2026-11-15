class_name EventClover
extends Node3D
## Клевер-четырёхлистник: вырастает в нескошенной траве и торчит над ней,
## поблёскивая. Скосил, пока не завял, — на удачу немного монет.

## Во сколько раз крупнее модели.
const SIZE := 2.4

var field: MowField
var life := 30.0
var coins := 10

var _model: MeshInstance3D
var _time := 0.0
var _glint_timer := 0.0
var _done := false


static func spawn(host: Node, at: Vector3, grass: MowField, seconds: float, reward: int) -> EventClover:
	var clover := EventClover.new()
	clover.name = "Clover"
	clover.field = grass
	clover.life = seconds
	clover.coins = reward
	# Хозяин (PlotEvents) стоит в начале координат: позиция задаётся до
	# добавления, чтобы _ready уже знал, где событие.
	clover.position = at
	host.add_child(clover)
	return clover


func _ready() -> void:
	add_to_group("event_clover")
	_model = Models.place(self, "clover", Vector3.ZERO, 1.0, randf() * TAU, false)
	_model.set_meta("no_bake", true)
	_model.scale = Vector3.ONE * 0.01
	# Крупнее настоящего: сверху над травой его должно быть видно.
	create_tween().tween_property(_model, "scale", Vector3.ONE * SIZE, 0.5).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	Juice.sparkle(get_parent(), global_position + Vector3.UP * 0.7, Color(0.75, 1.0, 0.5), 10)


func _process(delta: float) -> void:
	if _done:
		return
	_time += delta
	# Покачивается на ветру и поблёскивает.
	_model.rotation.z = sin(_time * 2.1) * 0.08
	_model.rotation.x = sin(_time * 1.7 + 1.0) * 0.06
	_model.rotation.y += delta * 0.6
	_glint_timer -= delta
	if _glint_timer <= 0.0:
		_glint_timer = 1.4
		Juice.glint(get_parent(), global_position + Vector3.UP * 1.2, Color(0.85, 1.0, 0.6))
	if field and field.get_height_at(global_position) == 0.0:
		_found()
	elif _time >= life:
		_wilt()


func _found() -> void:
	_done = true
	Sfx.play("chime", -6.0, 1.2)
	Juice.sparkle(get_parent(), global_position + Vector3.UP * 0.5, Color(0.8, 1.0, 0.5), 22)
	GameState.add_coins(coins, global_position + Vector3.UP * 0.6)
	GameState.toast(L.t("Четырёхлистник — на удачу! +%d монет") % coins)
	queue_free()


func _wilt() -> void:
	_done = true
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(SIZE, 0.05, SIZE), 0.8).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(queue_free)
