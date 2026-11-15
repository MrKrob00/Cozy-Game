class_name EventGift
extends Node3D
## Подарок события: письмо почтальона или посылка с воздушного шара.
## Если упал в нескошенную траву — спрятан, пока её не скосят (над травой
## изредка поблёскивает). Открытый подарок подпрыгивает на месте; герой
## подъезжает — подарок летит к нему, монеты в копилку.

## Ближе этого герой подбирает подарок, метры.
const PICKUP_DISTANCE := 1.4
const GLINT_EVERY := 2.2

var model_name := ""
var coins := 0
## Сообщение при находке (с %d — монеты).
var message := ""
var field: MowField

var _model: MeshInstance3D
var _player: Node3D
var _time := 0.0
var _glint_timer := 0.0
var _collected := false


static func spawn(host: Node, model: String, at: Vector3, reward: int, text: String, grass: MowField) -> EventGift:
	var gift := EventGift.new()
	gift.name = "Gift_" + model
	gift.model_name = model
	gift.coins = reward
	gift.message = text
	gift.field = grass
	# Хозяин (PlotEvents) стоит в начале координат: позиция задаётся до
	# добавления, чтобы _ready уже знал, где событие.
	gift.position = at
	host.add_child(gift)
	return gift


func _ready() -> void:
	add_to_group("event_gift")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_model = Models.place(self, model_name, Vector3.ZERO, 1.0, randf() * TAU, false)
	_model.set_meta("no_bake", true)


func is_hidden() -> bool:
	return field != null and field.contains(global_position) and field.get_height_at(global_position) > 0.0


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	var hidden := is_hidden()
	_model.visible = not hidden
	if hidden:
		_glint_timer -= delta
		if _glint_timer <= 0.0:
			_glint_timer = GLINT_EVERY * randf_range(0.8, 1.2)
			Juice.glint(get_parent(), global_position + Vector3.UP * 0.75)
		return
	_model.position.y = absf(sin(_time * 3.0)) * 0.08
	if _player and _player.global_position.distance_to(global_position) < PICKUP_DISTANCE:
		collect()


## Подарок достаётся герою.
func collect() -> void:
	if _collected:
		return
	_collected = true
	Sfx.play("find", -4.0)
	Juice.sparkle(get_parent(), global_position + Vector3.UP * 0.4)
	GameState.add_coins(coins, global_position + Vector3.UP * 0.6)
	if message != "":
		GameState.toast(L.t(message) % coins)
	GameState.save_game()
	var target := _player.global_position + Vector3.UP * 1.2 if _player else global_position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.2, 0.35)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
