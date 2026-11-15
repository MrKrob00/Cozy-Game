class_name Bureau
extends Interactable
## «Бюро находок» — почтовый ящик на площади. Здесь возвращают найденные
## вещи владельцам и получают за это монеты. Открывается, когда выкошена площадь.


func _ready() -> void:
	# Почтовый ящик на столбике — своя модель (tools/make_models.py).
	Models.place(self, "mailbox", Vector3.ZERO, 1.0)


func get_prompt() -> String:
	return "Бюро находок"


func can_interact(_player: Player) -> bool:
	var plot := Plot.of(self)
	return plot == null or plot.is_completed()


func interact(_player: Player) -> void:
	get_tree().call_group("hud", "open_bureau")
