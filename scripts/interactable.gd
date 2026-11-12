class_name Interactable
extends Node3D
## То, с чем игрок взаимодействует контекстной кнопкой: компостный ящик,
## зверёк, камень. Наследники переопределяют три метода ниже.

## Насколько близко должна быть «точка досягаемости» игрока (чуть впереди него).
@export var interact_radius := 1.6
## Срабатывает само, если игрок немного постоит рядом: кнопка не нужна.
## Подходит действиям, которые ничего не стоят и всегда желанны.
@export var auto_interact := false


func _enter_tree() -> void:
	add_to_group("interactable")


## Надпись на контекстной кнопке.
func get_prompt() -> String:
	return ""


func can_interact(_player: Player) -> bool:
	return true


func interact(_player: Player) -> void:
	pass
