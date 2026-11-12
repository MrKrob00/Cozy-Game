class_name Workshop
extends Interactable
## Мастерская в сарае. Открывается, когда найден ключ; здесь улучшают косилку.

## Сарай, который отпирается ключом.
@export var shed_path: NodePath
## Флаг находки-ключа.
@export var key_flag := "find_shed_key"

var _open := false


func _ready() -> void:
	if GameState.has_flag(key_flag):
		_unlock(false)


func _process(_delta: float) -> void:
	if not _open and GameState.has_flag(key_flag):
		_unlock(true)


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
		Sfx.play("plant", -4.0)
		GameState.toast("Ключ подошёл к сараю! Там мастерская — можно улучшить косилку")
