class_name Repairable
extends Interactable
## Починка объекта участка за монеты (фонтан, скамейка). Доступна, когда
## участок выкошен. Сам объект должен уметь set_repaired(animated).

## Уникальный идентификатор для сохранения.
@export var repair_id := ""
## Что чиним, в винительном падеже: «фонтан».
@export var title := "фонтан"
@export var cost := 80
## Объект, который меняет вид после починки.
@export var target_path: NodePath

var _repaired := false


func _enter_tree() -> void:
	super()
	add_to_group("repairable")


func _ready() -> void:
	interact_radius = 2.6
	if GameState.has_flag(_flag()):
		_repaired = true
		_apply(false)


func is_repaired() -> bool:
	return _repaired


func get_prompt() -> String:
	return "Починить %s — %d монет" % [title, cost]


func can_interact(_player: Player) -> bool:
	if _repaired:
		return false
	var plot := Plot.of(self)
	return plot == null or plot.is_completed()


func interact(_player: Player) -> void:
	if not GameState.spend_coins(cost):
		Sfx.play("deny")
		GameState.toast("Не хватает монет: нужно %d" % cost)
		return
	_repaired = true
	GameState.set_flag(_flag())
	_apply(true)
	Sfx.play("plant")
	Sfx.buzz(30)
	Juice.sparkle(self, global_position + Vector3.UP * 1.2, Color(0.7, 0.9, 1.0), 30)
	GameState.save_game()


func _apply(animated: bool) -> void:
	var target := get_node_or_null(target_path)
	if target and target.has_method("set_repaired"):
		target.set_repaired(animated)


func _flag() -> String:
	return "repaired_" + repair_id
