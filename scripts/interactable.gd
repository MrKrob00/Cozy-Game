class_name Interactable
extends Node3D
## То, с чем игрок взаимодействует контекстной кнопкой: компостный ящик,
## зверёк, камень. Наследники переопределяют три метода ниже.

## Насколько близко должна быть «точка досягаемости» игрока (чуть впереди него).
@export var interact_radius := 1.6


func _enter_tree() -> void:
	add_to_group("interactable")


## Надпись на контекстной кнопке.
func get_prompt() -> String:
	return ""


func can_interact(_player: Player) -> bool:
	return true


func interact(_player: Player) -> void:
	pass
