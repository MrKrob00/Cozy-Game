class_name Workshop
extends Interactable
## Мастерская в сарае. Открывается, когда найден ключ и двор выкошен целиком
## (тогда же возвращается Мастер и камера показывает его); здесь улучшают косилку.

## Сарай, который отпирается ключом.
@export var shed_path: NodePath
## Флаг находки-ключа.
@export var key_flag := "find_shed_key"

var _open := false


func _ready() -> void:
	if _ready_to_open():
		_unlock(false)


func _process(_delta: float) -> void:
	if not _open and _ready_to_open():
		_unlock(true)


func _ready_to_open() -> bool:
	var plot := Plot.of(self)
	return GameState.has_flag(key_flag) and (plot == null or GameState.is_plot_perfect(plot.plot_id))


func get_prompt() -> String:
	return "Мастерская"


func can_interact(_player: Player) -> bool:
	return _open


func interact(_player: Player) -> void:
	get_tree().call_group("hud", "open_workshop")


func _unlock(announce: bool) -> void:
	_open = true
	var shed := get_node_or_null(shed_path) as PlotProp
	if shed:
		shed.set_unlocked(announce)
	if announce:
		# Показ (камера, объяснение) — вместе с возвращением Мастера.
		Sfx.play("plant", -4.0)
